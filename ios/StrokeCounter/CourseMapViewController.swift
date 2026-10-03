import MapKit
import UIKit

// Full-screen satellite map of the current hole. Shows the hole's logged strokes and the marked hole,
// and measures from the current position to wherever the map is tapped. Each tap replaces the last one.
final class CourseMapViewController: UIViewController, MKMapViewDelegate, UIGestureRecognizerDelegate {
    typealias Measure = (CLLocation, CLLocationCoordinate2D, @escaping (String?) -> Void) -> Void

    private let data: CourseMapData
    private let measure: Measure
    private let mapView = MKMapView()
    private let badge = PaddedLabel()
    private var target: TargetAnnotation?

    private static let holeSpan: CLLocationDistance = 400   // meters across: about one hole

    init(data: CourseMapData, measure: @escaping Measure) {
        self.data = data
        self.measure = measure
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        mapView.preferredConfiguration = MKImageryMapConfiguration()
        mapView.showsUserLocation = true
        mapView.pointOfInterestFilter = .excludingAll
        mapView.delegate = self
        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "marker")
        mapView.frame = view.bounds
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(mapView)

        if let center = startCenter() {
            mapView.setRegion(MKCoordinateRegion(center: center, latitudinalMeters: Self.holeSpan,
                                                 longitudinalMeters: Self.holeSpan), animated: false)
        }
        mapView.addAnnotations(data.strokes.map(StrokeAnnotation.init))
        if let hole = data.holePosition { mapView.addAnnotation(HoleAnnotation(point: hole, hole: data.hole)) }

        // A single tap measures. It waits for a double tap to fail, so double-tap zooming still works.
        let doubleTap = UITapGestureRecognizer(target: nil, action: nil)
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = self
        let tap = UITapGestureRecognizer(target: self, action: #selector(mapTapped(_:)))
        tap.require(toFail: doubleTap)
        tap.delegate = self
        mapView.addGestureRecognizer(doubleTap)
        mapView.addGestureRecognizer(tap)

        setUpOverlay()
    }

    // Current position first, then the marked hole, then the last stroke.
    private func startCenter() -> CLLocationCoordinate2D? {
        data.fix?.coordinate ?? data.holePosition?.coordinate ?? data.strokes.last?.point.coordinate
    }

    private func setUpOverlay() {
        var config = UIButton.Configuration.filled()
        config.image = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(weight: .bold))
        config.cornerStyle = .capsule
        config.baseBackgroundColor = UIColor.black.withAlphaComponent(0.6)
        config.baseForegroundColor = .white
        let close = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })
        close.accessibilityLabel = "Close map"

        badge.font = .systemFont(ofSize: 20, weight: .bold)
        badge.textColor = .white
        badge.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        badge.layer.cornerRadius = 20
        badge.clipsToBounds = true
        badge.textAlignment = .center
        badge.text = data.hole > 0 ? "Hole \(data.hole) · Tap to measure" : "Tap to measure"

        for v in [close, badge] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            close.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            close.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8),
            close.widthAnchor.constraint(equalToConstant: 44),
            close.heightAnchor.constraint(equalToConstant: 44),
            badge.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            badge.topAnchor.constraint(equalTo: close.bottomAnchor, constant: 12),
            badge.heightAnchor.constraint(equalToConstant: 40),
            badge.widthAnchor.constraint(lessThanOrEqualTo: guide.widthAnchor, constant: -32)
        ])
    }

    @objc private func mapTapped(_ gesture: UITapGestureRecognizer) {
        let coordinate = mapView.convert(gesture.location(in: mapView), toCoordinateFrom: mapView)
        if let target { mapView.removeAnnotation(target) }
        let annotation = TargetAnnotation(coordinate: coordinate)
        target = annotation
        mapView.addAnnotation(annotation)
        updateDistance()
    }

    // The current position: the map's own when it has one, otherwise the fix the round had when the map opened.
    private func currentLocation() -> CLLocation? {
        if let location = mapView.userLocation.location, location.horizontalAccuracy >= 0 { return location }
        guard let fix = data.fix else { return nil }
        return CLLocation(coordinate: fix.coordinate, altitude: 0, horizontalAccuracy: fix.accuracy,
                          verticalAccuracy: -1, timestamp: Date())
    }

    private func updateDistance() {
        guard let target else { return }
        guard let from = currentLocation() else { badge.text = "No GPS position"; return }
        let coordinate = target.coordinate
        measure(from, coordinate) { [weak self] text in
            // A newer tap may have replaced the target while the distance was worked out.
            guard let self, self.target?.coordinate.latitude == coordinate.latitude,
                  self.target?.coordinate.longitude == coordinate.longitude else { return }
            self.badge.text = text ?? "–"
        }
    }

    // Walking keeps the distance to the tapped point up to date.
    func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
        updateDistance()
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if annotation is MKUserLocation { return nil }
        let view = mapView.dequeueReusableAnnotationView(withIdentifier: "marker", for: annotation) as! MKMarkerAnnotationView
        view.glyphText = nil
        view.glyphImage = nil
        view.displayPriority = .required
        switch annotation {
        case let stroke as StrokeAnnotation:
            view.markerTintColor = UIColor(red: 0.12, green: 0.32, blue: 0.20, alpha: 1)   // the app's fairway green
            view.glyphText = "\(stroke.number)"
        case is HoleAnnotation:
            view.markerTintColor = .systemRed
            view.glyphImage = UIImage(systemName: "flag.fill")
        default:
            view.markerTintColor = .systemOrange
            view.glyphImage = UIImage(systemName: "scope")
        }
        return view
    }

    // Taps on a marker select it (showing its title) instead of measuring.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let v = view {
            if v is MKAnnotationView { return false }
            view = v.superview
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

private final class StrokeAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let number: Int
    let title: String?

    init(_ stroke: CourseMapData.Stroke) {
        coordinate = stroke.point.coordinate
        number = stroke.number
        title = "\(stroke.number). \(stroke.club)"
    }
}

private final class HoleAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String?

    init(point: CourseMapData.Point, hole: Int) {
        coordinate = point.coordinate
        title = "Hole \(hole) (±\(Int(point.accuracy.rounded())) m)"
    }
}

private final class TargetAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    init(coordinate: CLLocationCoordinate2D) { self.coordinate = coordinate }
}

// A label with room around its text, for the distance badge.
private final class PaddedLabel: UILabel {
    private let insets = UIEdgeInsets(top: 0, left: 18, bottom: 0, right: 18)
    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }
    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height)
    }
}
