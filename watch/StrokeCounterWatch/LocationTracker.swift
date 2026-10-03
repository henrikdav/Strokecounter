import CoreLocation

// The watch's own GPS. It runs only while a round is shown and the app is in the foreground, and keeps the
// latest fix so a stroke can take its position at the moment it is logged without waiting.
// watchOS asks for permission itself the first time; if it is declined, strokes are simply logged without one.
final class LocationTracker: NSObject, CLLocationManagerDelegate {
    // A fix older than this is not used for a new stroke; same limit as the phone (FIX_MAX_AGE_MS).
    static let maxAge: TimeInterval = 30

    private let manager = CLLocationManager()
    private(set) var latest: CLLocation?
    private var running = false
    var onFix: ((CLLocation) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
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
