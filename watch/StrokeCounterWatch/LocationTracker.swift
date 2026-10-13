import CoreLocation

// The watch's own GPS. It runs only while a round is shown and the app is in the foreground, and keeps the
// latest fix so a stroke can take its position at the moment it is logged without waiting. To save battery it asks
// for the best accuracy short of navigation and a new fix only after 2 m of movement; when a fresh position matters
// right now (a swing, a raised wrist, a stroke logged without one) refresh() gives a fix every second for a few
// seconds, since standing still at the ball would otherwise give none.
// watchOS asks for permission itself the first time; if it is declined, strokes are simply logged without one.
final class LocationTracker: NSObject, CLLocationManagerDelegate {
    // A fix older than this is not used for a new stroke; same limit as the phone (FIX_MAX_AGE_MS).
    static let maxAge: TimeInterval = 30
    // On the recorded rounds a 2 m filter left the position at a stroke under a metre off (median), well inside
    // the GPS's own ~7 m, with a quarter of the fixes.
    static let distanceFilter: CLLocationDistance = 2
    static let refreshFor: TimeInterval = 8

    private let manager = CLLocationManager()
    private(set) var latest: CLLocation?
    private var running = false
    private var refreshUntil = Date.distantPast
    var onFix: ((CLLocation) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = Self.distanceFilter
        manager.activityType = .fitness
    }

    var freshFix: CLLocation? {
        guard let latest, -latest.timestamp.timeIntervalSinceNow < Self.maxAge else { return nil }
        return latest
    }

    func start() {
        guard !running else { return }
        running = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()   // continues in locationManagerDidChangeAuthorization
        case .denied, .restricted:
            break
        default:
            manager.startUpdatingLocation()
        }
    }

    // Every update for the next few seconds, whether the watch moves or not, then back to every 2 m.
    func refresh() {
        guard running else { return }
        refreshUntil = Date().addingTimeInterval(Self.refreshFor)
        manager.distanceFilter = kCLDistanceFilterNone
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.refreshFor + 0.1) { [weak self] in
            guard let self, Date() >= self.refreshUntil else { return }   // a later refresh extended it
            self.manager.distanceFilter = Self.distanceFilter
        }
    }

    func stop() {
        guard running else { return }
        running = false
        manager.stopUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard running else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: manager.startUpdatingLocation()
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0 else { return }
        latest = location
        onFix?(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Temporary failures are retried by CoreLocation; strokes meanwhile are logged without a position.
    }
}
