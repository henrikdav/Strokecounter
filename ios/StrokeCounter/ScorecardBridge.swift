import AVFoundation
import UIKit
import WebKit

// Scans a printed scorecard when the web app posts { type: "scan" } to the scorecard handler (New course).
// The ordinary camera takes one photo (retake or Use Photo), then ScorecardReader reads the text on the phone:
// nothing is sent anywhere and it works offline. The document camera was tried first, but it keeps capturing
// pages until Save, which was hard to handle with one card. The web app's scorecardScanned() gets
// { status: "reading" } while it reads, then { status: "ok", pages }, or "cancelled", "denied", "unsupported" or
// "failed", so the course editor stays as it was unless something was read.
final class ScorecardBridge: NSObject, WKScriptMessageHandler, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    static let handlerName = "scorecard"

    weak var webView: WKWebView?
    private var busy = false

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard !busy else { return }
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { reply(["status": "unsupported"]); return }
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
        let camera = UIImagePickerController()
        camera.sourceType = .camera
        camera.cameraCaptureMode = .photo
        camera.delegate = self
        busy = true
        top.present(camera, animated: true)
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        guard let image = info[.originalImage] as? UIImage, let cgImage = image.cgImage else {
            reply(["status": "failed"])
            return
        }
        send(["status": "reading"])
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        DispatchQueue.global(qos: .userInitiated).async {
            let page = ScorecardReader.read(cgImage, orientation: orientation)
            DispatchQueue.main.async { self.reply(["status": "ok", "pages": [page]]) }
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        reply(["status": "cancelled"])
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
