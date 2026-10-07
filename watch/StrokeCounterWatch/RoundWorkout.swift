import HealthKit

// A golf workout session that runs for the whole round. It keeps the app running in the background (with the
// workout-processing background mode), so raising the wrist returns to the app, it shows in the Dock, and GPS
// keeps running while the screen is off. The workout is never saved: the session is only ended, and nothing
// is added to the Health or Fitness app.
final class RoundWorkout: NSObject, HKWorkoutSessionDelegate {
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var starting = false
    private(set) var roundId: String?
    var onChange: (() -> Void)?

    var isRunning: Bool { session?.state == .running }

    // Asks for HealthKit permission the first time (the system shows it only once), then starts the session.
    // Must be called while the app is in the foreground.
    func start(roundId: String) {
        guard session == nil, !starting, HKHealthStore.isHealthDataAvailable() else { return }
        starting = true
        healthStore.requestAuthorization(toShare: [HKObjectType.workoutType()], read: []) { _, _ in
            DispatchQueue.main.async { self.begin(roundId: roundId) }
        }
    }

    private func begin(roundId: String) {
        starting = false
        guard session == nil else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .golf
        configuration.locationType = .outdoor
        // Without permission this fails; the round then works as before, with GPS only while the app is open.
        guard let session = try? HKWorkoutSession(healthStore: healthStore, configuration: configuration) else { return }
        session.delegate = self
        self.session = session
        self.roundId = roundId
        session.startActivity(with: Date())
    }

    // Ends the session without saving a workout. It is let go of at once, so a new round's session can start
    // right after, without waiting for watchOS to confirm the end.
    func end() {
        guard let session else { return }
        session.end()
        self.session = nil
        roundId = nil
        onChange?()
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState, date: Date) {
        DispatchQueue.main.async {
            // Only the current session counts; one already let go of by end() may still report its ending.
            if toState == .ended, workoutSession === self.session {
                self.session = nil
                self.roundId = nil
            }
            self.onChange?()
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            guard workoutSession === self.session else { return }
            self.session = nil
            self.roundId = nil
            self.onChange?()
        }
    }
}
