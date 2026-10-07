import CoreLocation

// What runs for the length of a round: the golf workout session and GPS, and the late fix for a stroke logged
// without a position. GPS runs while the workout runs, whatever is on screen and with the screen off; without a
// workout (HealthKit declined) only while the app is in the foreground. Both stop when the round is finished,
// removed or replaced, to save battery.
final class RoundSession {
    // A fix that arrived soon after a stroke was logged without one: (stroke id, round id, hole, position).
    var onLateFix: ((String, String, Int, WatchEvent.Position) -> Void)?

    private let location = LocationTracker()
    private let workout = RoundWorkout()
    private var roundId: String?
    private var finished = false
    private var appActive = true
    // The last stroke logged without a position, waiting a few seconds for a fix to fill it in.
    private var awaitingFix: (strokeId: String, roundId: String, hole: Int, loggedAt: Date)?
    private static let backfillWindow: TimeInterval = 10   // like the phone's single-fix timeout

    init() {
        location.onFix = { [weak self] fix in self?.lateFix(fix) }
        workout.onChange = { [weak self] in self?.updateLocation() }
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
        if workout.roundId != nil && (id == nil || id != workout.roundId || finished) {
            workout.end()
        }
        updateLocation()
    }

    // The hole screen is showing (app in the foreground): start the golf workout for this round if it is not
    // running yet. The first time, HealthKit asks for permission.
    func roundScreenShown() {
        if let roundId, !finished, workout.roundId != roundId {
            workout.end()   // a session left over from another round
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
