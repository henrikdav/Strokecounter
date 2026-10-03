import CoreLocation
import WebKit

// Opens the native satellite map when the web app posts to the courseMap handler. The message carries the
// current hole's data: { hole, strokes: [{ n, club, lat, lng, acc }], holePosition: { lat, lng, acc } | null,
// fix: { lat, lng, acc } | null }. The map is read-only: nothing is sent back to the round.
final class CourseMapBridge: NSObject, WKScriptMessageHandler {
    static let handlerName = "courseMap"

    weak var webView: WKWebView?

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let webView else { return }
        let data = CourseMapData(body)
        let map = CourseMapViewController(data: data) { [weak webView] from, to, completion in
            Self.measure(in: webView, from: from, to: to, completion: completion)
        }
        map.modalPresentationStyle = .fullScreen
        webView.topViewController?.present(map, animated: true)
    }

    // Distances use the web app's own meters() and fmtDist(), so the map shows exactly what the round screen
    // would: the same haversine distance, rounded the same way, with "≈" when the GPS accuracy is poor.
    private static func measure(in webView: WKWebView?, from: CLLocation, to: CLLocationCoordinate2D,
                                completion: @escaping (String?) -> Void) {
        guard let webView else { completion(nil); return }
        let c = from.coordinate
        let approx = from.horizontalAccuracy > 25
        let script = "fmtDist({ m: meters({ lat: \(c.latitude), lng: \(c.longitude) }, " +
                     "{ lat: \(to.latitude), lng: \(to.longitude) }), approx: \(approx) })"
        webView.evaluateJavaScript(script) { result, _ in completion(result as? String) }
    }
}

struct CourseMapData {
    struct Point {
        let coordinate: CLLocationCoordinate2D
        let accuracy: Double
    }
    struct Stroke {
        let number: Int
        let club: String
        let point: Point
    }

    let hole: Int
    let strokes: [Stroke]
    let holePosition: Point?
    let fix: Point?

    init(_ body: [String: Any]) {
        hole = (body["hole"] as? NSNumber)?.intValue ?? 0
        strokes = (body["strokes"] as? [[String: Any]] ?? []).compactMap { s in
            guard let point = Self.point(s), let n = (s["n"] as? NSNumber)?.intValue else { return nil }
            return Stroke(number: n, club: s["club"] as? String ?? "", point: point)
        }
        holePosition = Self.point(body["holePosition"])
        fix = Self.point(body["fix"])
    }

    private static func point(_ value: Any?) -> Point? {
        guard let p = value as? [String: Any],
              let lat = (p["lat"] as? NSNumber)?.doubleValue,
              let lng = (p["lng"] as? NSNumber)?.doubleValue else { return nil }
        return Point(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                     accuracy: (p["acc"] as? NSNumber)?.doubleValue ?? 0)
    }
}

extension UIView {
    // The view controller on top, to present over (alerts, the course map).
    var topViewController: UIViewController? {
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
