import CoreLocation
import WebKit

// Gives the web app CoreLocation positions. gps-shim.js replaces navigator.geolocation and posts
// { type: "start", highAccuracy } or { type: "stop" } here; positions and errors go back through
// window.__gpsBridge. Error codes follow GeolocationPositionError: 1 denied, 2 unavailable.
final class GPSBridge: NSObject, WKScriptMessageHandler, CLLocationManagerDelegate {
    static let handlerName = "gpsBridge"

    weak var webView: WKWebView?
    private let manager = CLLocationManager()
    private var wanted = false

    override init() {
        super.init()
        manager.delegate = self
        manager.distanceFilter = kCLDistanceFilterNone
    }

    // The shim, injected at document start in the main frame only.
    static var userScript: WKUserScript? {
        guard let url = Bundle.main.url(forResource: "gps-shim", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "start":
            let high = body["highAccuracy"] as? Bool ?? false
            manager.desiredAccuracy = high ? kCLLocationAccuracyBest : kCLLocationAccuracyHundredMeters
            wanted = true
            startIfAllowed()
        case "stop":
            wanted = false
            manager.stopUpdatingLocation()
        default:
            break
        }
    }

    private func startIfAllowed() {
        guard wanted else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()   // continues in locationManagerDidChangeAuthorization
        case .denied, .restricted:
            sendError(code: 1, message: "Location access denied")
        default:
            manager.startUpdatingLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .notDetermined { return }
        startIfAllowed()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0 else { return }
        let c = location.coordinate
        let t = Int64(location.timestamp.timeIntervalSince1970 * 1000)
        call("window.__gpsBridge.location({lat: \(c.latitude), lng: \(c.longitude), acc: \(location.horizontalAccuracy), t: \(t)})")
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let code = (error as? CLError)?.code
        // locationUnknown is temporary: CoreLocation keeps trying, and the shim's timeout covers a long wait.
        if code == .locationUnknown { return }
        if code == .denied { sendError(code: 1, message: "Location access denied") }
        else { sendError(code: 2, message: error.localizedDescription) }
    }

    private func sendError(code: Int, message: String) {
        let text = (try? JSONSerialization.data(withJSONObject: [message], options: []))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        call("window.__gpsBridge.error(\(code), \(text)[0])")
    }

    private func call(_ script: String) {
        webView?.evaluateJavaScript(script)
    }
}
