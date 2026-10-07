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
            self?.onFix?(fix)
        }
        workout.onChange = { [weak self] in
            guard let self else { return }
            if self.workout.isRunning, let until = self.announceUntil, Date() < until { self.announce() }
            self.updateLocation()
        }
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
    }

    // A stroke was just logged without a position: the next fix within the window is passed on for it.
    func awaitFix(strokeId: String, roundId: String, hole: Int) {
        awaitingFix = (strokeId, roundId, hole, Date())
    }

    func stopAwaitingFix() {
        awaitingFix = nil
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
