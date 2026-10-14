import CoreLocation
import Foundation

// What the screens use. It ties together the round as shown (RoundState: the phone's snapshot with this watch's
// unconfirmed events on top), the sync with the phone (SyncClient) and what runs during a round (RoundSession:
// workout and GPS), keeps the choices made on the watch, and saves state so it survives a restart.
// The protocol is described in docs/watch-sync.md.
final class WatchStore: ObservableObject {
    @Published private(set) var state: RoundState
    // A snapshot came from a newer iPhone app than this watch app understands. It is ignored (the round already
    // here keeps working, and events sent from here are still accepted) and the watch asks to be updated.
    @Published var phoneIsNewer = false
    // The latest GPS fix, published so the shot distance updates while walking.
    @Published private(set) var lastFix: CLLocation?
    // When the last swing was found (RoundSession.lastSwing), so the screens can show the club list after it.
    @Published private(set) var swingTime: Date?
    // Counts every change to the swing (found, walked away from, used), so the screens can react to each.
    @Published private(set) var swingChanges = 0

    private let sync = SyncClient()
    private let session = RoundSession()
    private let defaults = UserDefaults.standard
    private static var now: Double { (Date().timeIntervalSince1970 * 1000).rounded() }

    init() {
        let snapshot = defaults.data(forKey: "snapshot").flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
        let outbox = defaults.data(forKey: "outbox").flatMap { try? JSONDecoder().decode([WatchEvent].self, from: $0) } ?? []
        state = RoundState(snapshot: snapshot, outbox: outbox)
        defaults.removeObject(forKey: "pickedClub")   // from when a club could be picked before logging
        sync.onSnapshot = { [weak self] json in self?.receive(snapshotJSON: json) }
        sync.outbox = { [weak self] in self?.state.outbox ?? [] }
        session.onLateFix = { [weak self] strokeId, roundId, hole, position in
            self?.change { $0.fillPosition(position, strokeId: strokeId, roundId: roundId, hole: hole) }
        }
        session.onFix = { [weak self] fix in self?.lastFix = fix }
        session.onRecording = { [weak self] folder in self?.sync.sendRecording(folder) }
        session.onSwingChange = { [weak self] in
            self?.swingTime = self?.session.lastSwing?.time
            self?.swingChanges += 1
        }
        session.currentHole = { [weak self] in self?.state.currentHole }
        sync.activeRecording = { [weak self] in self?.session.recorder.currentFolder }
        session.setSwingDetection(state.swingDetection)
        session.roundChanged(id: state.round?.id, finished: state.isRoundFinished)
        sync.activate()
    }

    #if DEBUG
    // For the Xcode previews (PreviewData): a store showing the given round and fix, with nothing connected,
    // nothing started and nothing saved.
    init(preview snapshot: Snapshot?, fix: CLLocation?) {
        state = RoundState(snapshot: snapshot)
        lastFix = fix
    }
    #endif

    // MARK: What the screens show

    var round: Snapshot.Round? { state.round }
    var bag: [String] { state.bag }
    var currentHole: Int? { state.currentHole }
    var isRoundFinished: Bool { state.isRoundFinished }
    func hole(_ number: Int) -> Snapshot.Hole? { state.hole(number) }
    func isLastHole(_ number: Int) -> Bool { state.isLastHole(number) }
    func isLocked(_ hole: Int) -> Bool { state.isLocked(hole) }
    func strokes(on hole: Int) -> [Snapshot.Stroke] { state.strokes(on: hole) }
    func extra(_ hole: Int) -> Int? { state.extra(hole) }
    func holePosition(_ hole: Int) -> Snapshot.HolePosition? { state.holePosition(hole) }

    // The latest fix if it is recent enough to measure from (the same 30 s as for a new stroke), else nil.
    var freshFix: WatchEvent.Position? {
        guard let fix = lastFix, -fix.timestamp.timeIntervalSinceNow < LocationTracker.maxAge else { return nil }
        return WatchEvent.Position(lat: fix.coordinate.latitude, lng: fix.coordinate.longitude, acc: fix.horizontalAccuracy)
    }

    func shotDistance(on hole: Int) -> RoundState.ShotDistance { state.shotDistance(on: hole, fix: freshFix) }

    // The club the next stroke on the hole is logged with (RoundState.club(on:)).
    func club(on hole: Int) -> String { state.club(on: hole) }

    // MARK: Actions

    // Logs a stroke with the club; its club and modifiers can be changed right after (editStroke). Never waits for
    // GPS. The position is where the last swing was played, when one was found in the last minute (the player may
    // have walked on since); else the latest fix if it is recent; else it is filled in shortly. A swing is used
    // for one stroke only. fromSwingList: logged from the club list shown after a swing.
    @discardableResult
    func logStroke(club: String, hole: Int, fromSwingList: Bool = false) -> Snapshot.Stroke? {
        // From the club list: the swing it was shown for. With +1: a swing in the last minute.
        let swingPosition = fromSwingList ? session.swingToLog?.position : session.recentSwing?.position
        let fix = swingPosition ?? session.freshFix
        let id = UUID().uuidString.lowercased()
        guard let event = change({ $0.logStroke(id: id, club: club, mods: [], hole: hole, t: Self.now, position: fix) }),
              let roundId = state.round?.id else { return nil }
        if fix == nil { session.awaitFix(strokeId: id, roundId: roundId, hole: hole) } else { session.stopAwaitingFix() }
        session.clearSwing()
        if let stroke = event.stroke {
            session.recorder.noteStroke(stroke, hole: hole, fromSwingList: fromSwingList, swingPosition: swingPosition != nil)
        }
        return event.stroke
    }

    // MARK: Swings

    // The club list is shown when the wrist is raised within a minute of a swing, on a hole that takes strokes,
    // unless it was cancelled for that swing.
    func swingWaiting(on hole: Int) -> Bool {
        guard swingTime != nil, session.swingToLog != nil else { return false }
        return !state.isRoundFinished && !state.isLocked(hole)
    }

    // When the swing the club list is for was played, shown as its title once it is more than a minute ago.
    var swingToLogTime: Date? { session.swingToLog?.time }

    func swingListShown() {
        session.recorder.note("swing-list")
    }

    // Cancel on the club list: nothing is logged and the list goes, not to come back for this swing. The swing
    // keeps its position for a minute, in case the stroke is logged with +1 instead.
    func cancelSwingList() {
        session.recorder.note("swing-cancel")
        session.closeSwingList()
    }

    // Changes a logged stroke's club and modifiers (all of them), from the screen shown after logging.
    func editStroke(_ id: String, hole: Int, club: String, mods: Set<Modifier>) {
        if let event = change({ $0.editStroke(id: id, hole: hole, club: club, mods: mods, t: Self.now) }) {
            session.recorder.noteEdit(strokeId: id, club: club, mods: event.mods ?? [])
        }
    }

    func removeStroke(_ id: String, hole: Int) {
        if change({ $0.removeStroke(id: id, hole: hole, t: Self.now) }) != nil { session.recorder.noteRemoved(strokeId: id) }
    }

    // Locks the current shot's distance where the watch is now, as its landing. False when there is no fix.
    @discardableResult
    func lockDistance(strokeId: String, hole: Int) -> Bool {
        guard let fix = freshFix else { return false }
        return change { $0.lockLanding(strokeId: strokeId, hole: hole, position: fix, t: Self.now) } != nil
    }

    // Marks the hole where the watch is now. False when there is no fix (or the hole is locked).
    @discardableResult
    func markHole(_ hole: Int) -> Bool {
        guard let fix = freshFix else { return false }
        return change { $0.markHole(hole, position: fix, t: Self.now) } != nil
    }

    func finishHole(_ hole: Int) {
        change { $0.finishHole(hole, t: Self.now) }
        session.roundChanged(id: state.round?.id, finished: state.isRoundFinished)
    }

    // MARK: Round lifecycle

    // The hole screen is showing: starts the round's workout (and with it GPS) before the first tap.
    func roundScreenShown() {
        session.roundScreenShown()
    }

    // Raising the wrist also asks the phone for its current round, so what was done on the phone (a stroke, Done,
    // Finish round) shows at once even if its snapshot is still on the way.
    func setAppActive(_ active: Bool) {
        session.setAppActive(active)
        if active { sync.requestSnapshot() }
    }

    // The iPhone app launched this app for a new round: start its workout (and GPS), and ask for the round in
    // case its snapshot hasn't arrived yet.
    func startedFromPhone() {
        session.startedFromPhone()
        sync.requestSnapshot()
    }

    // MARK: Sync and storage

    // Applies a change to the round, then saves and sends the event it made, if any.
    @discardableResult
    private func change(_ apply: (inout RoundState) -> WatchEvent?) -> WatchEvent? {
        guard let event = apply(&state) else { return nil }
        saveOutbox()
        sync.send([event])
        return event
    }

    private func receive(snapshotJSON json: String) {
        switch state.receive(snapshotJSON: json) {
        case .applied:
            phoneIsNewer = false
            defaults.set(Data(json.utf8), forKey: "snapshot")
            saveOutbox()
            session.setSwingDetection(state.swingDetection)
            session.roundChanged(id: state.round?.id, finished: state.isRoundFinished)
        case .newerVersion:
            phoneIsNewer = true
        case .stale:
            break
        case .unreadable:
            break
        }
    }

    private func saveOutbox() {
        defaults.set(try? JSONEncoder().encode(state.outbox), forKey: "outbox")
    }
}
