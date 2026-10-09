import AVFoundation
import UIKit
import VisionKit
import WebKit

// Scans a printed scorecard when the web app posts { type: "scan" } to the scorecard handler (New course).
// The document camera finds and straightens the card (several pages, e.g. front and back, are fine), then
// ScorecardReader reads the text on the phone: nothing is sent anywhere and it works offline. The web app's
// scorecardScanned() gets { status: "reading" } while it reads, then { status: "ok", pages }, or "cancelled",
// "denied", "unsupported" or "failed", so the course editor stays as it was unless something was read.
final class ScorecardBridge: NSObject, WKScriptMessageHandler, VNDocumentCameraViewControllerDelegate {
    static let handlerName = "scorecard"

    weak var webView: WKWebView?
    private var busy = false

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard !busy else { return }
        guard VNDocumentCameraViewController.isSupported else { reply(["status": "unsupported"]); return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            present()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { granted ? self.present() : self.reply(["status": "denied"]) }
            }
        default:
            reply(["status": "denied"])
        }
    }

    private func present() {
        guard let top = webView?.topViewController else { reply(["status": "failed"]); return }
        let camera = VNDocumentCameraViewController()
        camera.delegate = self
        busy = true
        top.present(camera, animated: true)
    }

    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
        let images = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
        controller.dismiss(animated: true)
        send(["status": "reading"])
        DispatchQueue.global(qos: .userInitiated).async {
            let pages = images.compactMap { image -> [String: Any]? in
                guard let cgImage = image.cgImage else { return nil }
                return ScorecardReader.read(cgImage, orientation: CGImagePropertyOrientation(image.imageOrientation))
            }
            DispatchQueue.main.async { self.reply(["status": "ok", "pages": pages]) }
        }
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        controller.dismiss(animated: true)
        reply(["status": "cancelled"])
    }

    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
        controller.dismiss(animated: true)
        reply(["status": "failed"])
    }

    private func reply(_ result: [String: Any]) {
        busy = false
        send(result)
    }

    private func send(_ result: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: result),
              let json = String(data: data, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("scorecardScanned(\(json))")
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
