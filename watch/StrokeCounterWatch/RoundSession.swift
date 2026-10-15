import CoreLocation
import WatchKit

// What runs for the length of a round: the golf workout session and GPS, and the late fix for a stroke logged
// without a position. GPS runs while the workout runs, whatever is on screen and with the screen off; without a
// workout (HealthKit declined) only while the app is in the foreground. Both stop when the round is finished,
// removed or replaced, to save battery.
final class RoundSession {
    // A fix that arrived soon after a stroke was logged without one: (stroke id, round id, hole, position).
    var onLateFix: ((String, String, Int, WatchEvent.Position) -> Void)?
    // Every new fix, for what is shown live (the distance of the current shot).
    var onFix: ((CLLocation) -> Void)?
    // A swing recording finished: its folder, to send to the phone.
    var onRecording: ((URL) -> Void)?
    // A swing was found, or the one kept was used or dropped.
    var onSwingChange: (() -> Void)?

    // Follows the motion while the workout runs, finds swings and records the data (SwingRecorder).
    let recorder = SwingRecorder()

    // The last swing found, where it was played from and on which hole. It is kept until a stroke is logged, the
    // next swing replaces it (so practice swings before a shot count as one), or the hole changes. Within a minute it
    // gives a stroke logged with +1 its position, and raising the wrist shows the club list (WatchStore). After
    // that, walking 15 m away from it without logging means the shot was likely forgotten (on the recorded rounds
    // 81 of 99 shots against 18 of 119 other swings): one buzz, and the club list shows on the next wrist raise.
    struct Swing {
        let time: Date
        let hole: Int?
        var position: WatchEvent.Position?
        var listClosed = false   // the club list was cancelled: not shown again for this swing
        var walkedAway = false   // the player has since walked 15 m from it
    }
    private(set) var lastSwing: Swing?
    static let swingWindow: TimeInterval = 60
    static let walkedAwayDistance = 15.0
    // The hole being played, so a swing belongs to it (WatchStore).
    var currentHole: () -> Int? = { nil }
    // A swing walked away from and never logged, now overtaken by the next swing: log it as a stroke (WatchStore).
    var onForgottenSwing: ((Swing) -> Void)?
    // Swing detection, on unless switched off in the phone's Settings (it comes with the snapshot).
    private var detecting = true

    private let location = LocationTracker()
    private let workout = RoundWorkout()
    private var roundId: String?
    private var finished = false
    private var appActive = true
    // Set once the hole screen has been shown or the iPhone app has started this app for a round. From then on
    // the workout follows the round: it starts for an unfinished round, also one that arrives later, and ends with it.
    private var wantsWorkout = false
    // The iPhone app launched this app: buzz once, so the player notices. Until this time the next workout that
    // starts running is announced (the round's snapshot may still be on its way); nil once announced.
    private var announceUntil: Date?
    // The last stroke logged without a position, waiting a few seconds for a fix to fill it in.
    private var awaitingFix: (strokeId: String, roundId: String, hole: Int, loggedAt: Date)?
    private static let backfillWindow: TimeInterval = 10   // like the phone's single-fix timeout

    init() {
        location.onFix = { [weak self] fix in
            self?.lateFix(fix)
            self?.swingFix(fix)
            self?.checkWalkedAway(fix)
            self?.recorder.noteFix(fix)
            self?.onFix?(fix)
        }
        workout.onChange = { [weak self] in
            guard let self else { return }
            if self.workout.isRunning, let until = self.announceUntil, Date() < until { self.announce() }
            self.updateLocation()
            self.updateRecording()
        }
        recorder.onFinished = { [weak self] folder in self?.onRecording?(folder) }
        recorder.onSwing = { [weak self] time, swing in self?.swingFound(at: time, swing) }
    }

    // The latest fix if it is recent enough for a new stroke (LocationTracker.maxAge), else nil.
    var freshFix: WatchEvent.Position? {
        location.freshFix.map { WatchEvent.Position(lat: $0.coordinate.latitude, lng: $0.coordinate.longitude, acc: $0.horizontalAccuracy) }
    }

    // The round on the watch changed (a new snapshot, or a hole finished here). Ends the workout, without saving
    // it, when the round is finished, removed, or replaced by another round.
    func roundChanged(id: String?, finished: Bool) {
        roundId = id
        self.finished = finished
        syncWorkout()
    }

    // The hole screen is showing (app in the foreground): start the golf workout for this round if it is not
    // running yet. The first time, HealthKit asks for permission.
    func roundScreenShown() {
        wantsWorkout = true
        syncWorkout()
    }

    // The iPhone app started a round and launched this app with a workout configuration (startWatchApp): start
    // the workout now, or as soon as the round arrives.
    func startedFromPhone() {
        wantsWorkout = true
        announceUntil = Date().addingTimeInterval(20)
        // A workout already running (Continue while playing) is announced at once; otherwise when it starts.
        if workout.isRunning { announce() }
        syncWorkout()
    }

    // A double buzz with the notification haptic, the one made to be felt on the wrist; the second waits for the
    // first to finish, since watchOS drops a haptic that starts while another plays. Played while a workout session
    // runs, which also lets it play with the app in the background.
    private func announce() {
        announceUntil = nil
        WKInterfaceDevice.current().play(.notification)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { WKInterfaceDevice.current().play(.notification) }
    }

    // Ends a workout that belongs to no current, unfinished round, and starts one for the round when wanted.
    private func syncWorkout() {
        if workout.roundId != nil && (roundId == nil || workout.roundId != roundId || finished) {
            workout.end()
        }
        if wantsWorkout, let roundId, !finished, workout.roundId != roundId {
            workout.start(roundId: roundId)
        }
        updateLocation()
    }

    func setAppActive(_ active: Bool) {
        appActive = active
        updateLocation()
        // The wrist was raised, likely to log or mark something: have a fresh position ready.
        if active { location.refresh() }
    }

    // A fix every second for a few seconds, e.g. while the player stands at the cup to mark it.
    func refreshLocation() {
        location.refresh()
    }

    // A stroke was just logged without a position: the next fix within the window is passed on for it.
    func awaitFix(strokeId: String, roundId: String, hole: Int) {
        awaitingFix = (strokeId, roundId, hole, Date())
        location.refresh()   // standing still gives no new fix otherwise
    }

    func stopAwaitingFix() {
        awaitingFix = nil
    }

    // Motion is followed exactly while the round's workout runs.
    private func updateRecording() {
        if workout.isRunning, let id = workout.roundId {
            if !recorder.isRunning { recorder.start(roundId: id, detecting: detecting) }
        } else if recorder.isRunning {
            recorder.stop()
            clearSwing()
        }
    }

    // MARK: Swings

    func setSwingDetection(_ on: Bool) {
        guard on != detecting else { return }
        detecting = on
        recorder.setDetecting(on)
        if !on { clearSwing() }
    }

    // The swing found in the last minute, if any: its position goes to a stroke logged with +1.
    var recentSwing: Swing? {
        guard let swing = lastSwing, -swing.time.timeIntervalSinceNow <= Self.swingWindow else { return nil }
        return swing
    }

    // The swing the club list is for: one found in the last minute, or one walked away from without logging,
    // on the hole being played and not cancelled.
    var swingToLog: Swing? {
        guard let swing = lastSwing, !swing.listClosed, swing.hole == currentHole(),
              swing.walkedAway || -swing.time.timeIntervalSinceNow <= Self.swingWindow else { return nil }
        return swing
    }

    // The club list was cancelled: it is not shown again for this swing, but the swing keeps its position for a
    // stroke logged with +1 within the minute.
    func closeSwingList() {
        lastSwing?.listClosed = true
    }

    // The swing is used (a stroke was logged).
    func clearSwing() {
        guard lastSwing != nil else { return }
        lastSwing = nil
        onSwingChange?()
    }

    // The swing that would be logged automatically: walked away from, not logged, not cancelled.
    var forgottenSwing: Swing? {
        guard let swing = lastSwing, swing.walkedAway, !swing.listClosed, swing.hole != nil else { return nil }
        return swing
    }

    private func swingFound(at time: Date, _ swing: SwingDetector.Swing) {
        // The player walked away from the last swing without logging it and has now swung again: that was a shot.
        if let forgotten = forgottenSwing { onForgottenSwing?(forgotten) }
        // The player stands still at the ball, so the latest fix (no older than 30 s, within 2 m of the ball) is
        // where the swing was; without one, the first fix of a refresh fills it in (swingFix).
        lastSwing = Swing(time: time, hole: currentHole(), position: freshFix)
        if lastSwing?.position == nil { location.refresh() }
        recorder.noteSwing(at: time, swing, position: lastSwing?.position)
        onSwingChange?()
    }

    // A swing found without a fix gets the first one within 10 s.
    private func swingFix(_ fix: CLLocation) {
        guard let swing = lastSwing, swing.position == nil, fix.timestamp.timeIntervalSince(swing.time) <= 10 else { return }
        lastSwing?.position = WatchEvent.Position(lat: fix.coordinate.latitude, lng: fix.coordinate.longitude, acc: fix.horizontalAccuracy)
    }

    // Walking 15 m from an unlogged swing: buzz once, and the club list waits for the next wrist raise.
    private func checkWalkedAway(_ fix: CLLocation) {
        guard let swing = lastSwing, !swing.walkedAway, !swing.listClosed, let from = swing.position,
              swing.hole == currentHole() else { return }
        let here = WatchEvent.Position(lat: fix.coordinate.latitude, lng: fix.coordinate.longitude, acc: fix.horizontalAccuracy)
        let distance = meters(from, here)
        guard distance >= Self.walkedAwayDistance else { return }
        lastSwing?.walkedAway = true
        recorder.note("swing-reminder")
        // Two buzzes, like when the phone starts the watch app: one alone is easily missed while walking.
        WKInterfaceDevice.current().play(.notification)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { WKInterfaceDevice.current().play(.notification) }
        onSwingChange?()
    }

    private func updateLocation() {
        let playing = roundId != nil && !finished && (workout.isRunning || appActive)
        if playing { location.start() } else { location.stop() }
    }

    private func lateFix(_ fix: CLLocation) {
        guard let waiting = awaitingFix else { return }
        awaitingFix = nil
        guard -waiting.loggedAt.timeIntervalSinceNow <= Self.backfillWindow else { return }
        let position = WatchEvent.Position(lat: fix.coordinate.latitude, lng: fix.coordinate.longitude, acc: fix.horizontalAccuracy)
        onLateFix?(waiting.strokeId, waiting.roundId, waiting.hole, position)
    }
}
