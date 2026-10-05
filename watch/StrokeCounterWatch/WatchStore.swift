import CoreLocation
import Foundation
import WatchConnectivity

// Holds the round from the phone plus what was done on the watch and not yet confirmed by the phone (the outbox).
// What the screens show is the phone's round with the outbox applied on top, so a stroke appears at once even
// when the phone is out of reach. Events go to the phone with transferUserInfo, which the system queues and
// delivers even if the phone app is in the background; the phone can also ask for the outbox again ("flush").
final class WatchStore: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var snapshot: Snapshot?
    @Published private(set) var outbox: [WatchEvent] = []
    @Published var lastClub: String?
    @Published var armedMods: Set<Modifier> = []

    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil
    private let defaults = UserDefaults.standard
    private let location = LocationTracker()
    private let workout = RoundWorkout()
    private var appActive = true
    // The last stroke logged without a position, waiting a few seconds for a fix to fill it in.
    private var awaitingFix: (id: String, roundId: String, hole: Int, loggedAt: Date)?
    private static let backfillWindow: TimeInterval = 10   // like the phone's single-fix timeout
    private static var now: Double { (Date().timeIntervalSince1970 * 1000).rounded() }

    override init() {
        super.init()
        if let data = defaults.data(forKey: "snapshot") { snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) }
        if let data = defaults.data(forKey: "outbox") { outbox = (try? JSONDecoder().decode([WatchEvent].self, from: data)) ?? [] }
        lastClub = defaults.string(forKey: "lastClub")
        location.onFix = { [weak self] fix in self?.backfill(fix) }
        workout.onChange = { [weak self] in self?.updateLocation() }
        session?.delegate = self
        session?.activate()
    }

    // MARK: What the screens show

    var round: Snapshot.Round? { snapshot?.round }

    var bag: [String] { snapshot?.bag ?? [] }

    // The club the next stroke is logged with: the one picked here last, else the phone's.
    var club: String { lastClub ?? snapshot?.club ?? bag.first ?? "Driver" }

    // Picks the club for the next stroke without logging anything, like arming a modifier.
    func selectClub(_ club: String) {
        lastClub = club
        defaults.set(club, forKey: "lastClub")
    }

    // The hole to play: the phone's current hole, or the one after a hole finished here and not yet confirmed.
    var currentHole: Int? {
        guard let round else { return nil }
        let finished = outbox.filter { $0.type == .finish && $0.roundId == round.id }.map(\.hole)
        guard let last = finished.max() else { return round.currentHole }
        let lastHole = round.holes.last?.number ?? last
        return max(round.currentHole, min(last + 1, lastHole))
    }

    func hole(_ number: Int) -> Snapshot.Hole? {
        round?.holes.first { $0.number == number }
    }

    // A locked hole takes no strokes and no removals. Locked on the phone, or finished here and not yet confirmed.
    // The phone enforces the same rule when the events arrive (applyWatchEvents in web/index.html).
    func isLocked(_ hole: Int) -> Bool {
        guard let round else { return false }
        return round.locked.contains(hole) ||
            outbox.contains { $0.type == .finish && $0.roundId == round.id && $0.hole == hole }
    }

    func isLastHole(_ number: Int) -> Bool {
        round?.holes.last?.number == number
    }

    // The phone's strokes for the hole, minus strokes removed here, plus strokes added here, in playing order.
    func strokes(on hole: Int) -> [Snapshot.Stroke] {
        guard let round else { return [] }
        let mine = outbox.filter { $0.roundId == round.id && $0.hole == hole }
        let removed = Set(mine.compactMap(\.id)).union(round.removed)
        var list = (round.strokes[String(hole)] ?? []).filter { !removed.contains($0.id) }
        for event in mine where event.type == .add {
            if let stroke = event.stroke, !removed.contains(stroke.id), !list.contains(where: { $0.id == stroke.id }) {
                list.append(stroke)
            }
        }
        return list.sorted { $0.t < $1.t }
    }

    // MARK: Actions

    // Logs a stroke with the club and the armed modifiers, which then reset like on the phone.
    @discardableResult
    func logStroke(club: String, hole: Int) -> Snapshot.Stroke? {
        guard let round, !isLocked(hole) else { return nil }
        let mods = Modifier.allCases.filter { armedMods.contains($0) }.map(\.rawValue)
        var stroke = Snapshot.Stroke(id: UUID().uuidString.lowercased(), club: club, mods: mods,
                                     t: (Date().timeIntervalSince1970 * 1000).rounded())
        // Never wait for GPS: take the latest fix if it is recent, otherwise log now and fill it in shortly.
        if let fix = location.freshFix {
            stroke.lat = fix.coordinate.latitude
            stroke.lng = fix.coordinate.longitude
            stroke.acc = fix.horizontalAccuracy
            awaitingFix = nil
        } else {
            awaitingFix = (stroke.id, round.id, hole, Date())
        }
        selectClub(club)
        armedMods = []
        send(WatchEvent(type: .add, roundId: round.id, hole: hole, stroke: stroke))
        return stroke
    }

    func removeStroke(_ id: String, hole: Int) {
        guard let round, !isLocked(hole) else { return }
        send(WatchEvent(type: .remove, roundId: round.id, hole: hole, id: id, t: Self.now))
    }

    func finishHole(_ hole: Int) {
        guard let round else { return }
        send(WatchEvent(type: .finish, roundId: round.id, hole: hole, t: Self.now))
        endWorkoutIfRoundOver()
    }

    // MARK: Round lifecycle (workout session and GPS)

    // The round is over when it is finished on the phone's scorecard. Only the phone finishes (and unlocks) a
    // round; finishing the last hole does not. A finished round arrives with every hole locked, so it is read-only.
    var isRoundFinished: Bool {
        round?.finished == true
    }

    // The hole screen is showing (app in the foreground): start the golf workout for this round if it is not
    // running yet. The first time, HealthKit asks for permission.
    func roundScreenShown() {
        if let round, !isRoundFinished, workout.roundId != round.id {
            workout.end()   // a session left over from another round
            workout.start(roundId: round.id)
        }
        updateLocation()
    }

    func setAppActive(_ active: Bool) {
        appActive = active
        updateLocation()
    }

    // GPS runs for the whole round while the workout session runs, whatever is on screen and with the screen off.
    // Without a session (HealthKit declined) it runs only while the app is in the foreground, as before.
    private func updateLocation() {
        let playing = round != nil && !isRoundFinished && (workout.isRunning || appActive)
        if playing { location.start() } else { location.stop() }
    }

    // Ends the workout (without saving it) when the round is finished, removed, or replaced by another round.
    private func endWorkoutIfRoundOver() {
        if workout.roundId != nil && (round == nil || round?.id != workout.roundId || isRoundFinished) {
            workout.end()
        }
        updateLocation()
    }

    // A fix that arrives soon after a stroke was logged without one is added to that stroke.
    private func backfill(_ fix: CLLocation) {
        guard let waiting = awaitingFix else { return }
        awaitingFix = nil
        guard -waiting.loggedAt.timeIntervalSinceNow <= Self.backfillWindow, round?.id == waiting.roundId,
              strokes(on: waiting.hole).contains(where: { $0.id == waiting.id }) else { return }
        let position = WatchEvent.Position(lat: fix.coordinate.latitude, lng: fix.coordinate.longitude,
                                           acc: fix.horizontalAccuracy)
        // Also put it on the queued add, so a resend carries the position too.
        if let i = outbox.firstIndex(where: { $0.type == .add && $0.stroke?.id == waiting.id }) {
            outbox[i].stroke?.lat = position.lat
            outbox[i].stroke?.lng = position.lng
            outbox[i].stroke?.acc = position.acc
        }
        send(WatchEvent(type: .position, roundId: waiting.roundId, hole: waiting.hole, id: waiting.id, position: position))
    }

    // MARK: Sync

    private func send(_ event: WatchEvent) {
        outbox.append(event)
        saveOutbox()
        transfer([event])
    }

    // Queued delivery always, so the events reach the phone even if its app is in the background or closed;
    // a live message as well when the phone app is running, so they show up there within a second.
    // The phone ignores the second copy.
    private func transfer(_ events: [WatchEvent]) {
        guard let session, session.activationState == .activated, !events.isEmpty, let json = encode(events) else { return }
        session.transferUserInfo(["events": json])
        if session.isReachable {
            session.sendMessage(["events": json], replyHandler: nil, errorHandler: nil)
        }
    }

    private func encode(_ events: [WatchEvent]) -> String? {
        (try? JSONEncoder().encode(events)).flatMap { String(data: $0, encoding: .utf8) }
    }

    private func saveOutbox() {
        defaults.set(try? JSONEncoder().encode(outbox), forKey: "outbox")
    }

    // A new snapshot from the phone. Events it confirms are dropped from the outbox, and so are events for a
    // round the phone no longer shows (those were already queued for delivery when they were made).
    private func apply(snapshotJSON json: String) {
        guard let new = try? JSONDecoder().decode(Snapshot.self, from: Data(json.utf8)) else { return }
        snapshot = new
        defaults.set(Data(json.utf8), forKey: "snapshot")
        if let round = new.round {
            outbox.removeAll { $0.roundId != round.id || $0.isConfirmed(by: round) }
        } else {
            outbox.removeAll()
        }
        saveOutbox()
        endWorkoutIfRoundOver()
    }

    // Asks the phone for its current round instead of waiting for the application context, which can be slow
    // or missing (for example right after this app was installed). Wakes the phone app if needed.
    private func requestSnapshot() {
        guard let session, session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(["type": "snapshot-request"], replyHandler: { [weak self] reply in
            guard let json = reply["snapshot"] as? String else { return }
            DispatchQueue.main.async { self?.apply(snapshotJSON: json) }
        }, errorHandler: nil)
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            if let json = session.receivedApplicationContext["snapshot"] as? String { self.apply(snapshotJSON: json) }
            self.requestSnapshot()
            // Anything made before the session was ready goes now; the phone ignores repeats.
            self.transfer(self.outbox)
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        DispatchQueue.main.async { self.requestSnapshot() }
    }

    // A live copy of the snapshot, sent while this app is running.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let json = message["snapshot"] as? String else { return }
        DispatchQueue.main.async { self.apply(snapshotJSON: json) }
    }

    func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        guard let json = context["snapshot"] as? String else { return }
        DispatchQueue.main.async { self.apply(snapshotJSON: json) }
    }

    // The phone came to the foreground and asks for everything it has not confirmed yet.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        DispatchQueue.main.async {
            replyHandler(["events": self.encode(self.outbox) ?? "[]"])
        }
    }
}
