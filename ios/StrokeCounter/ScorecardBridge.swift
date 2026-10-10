import AVFoundation
import PhotosUI
import UIKit
import WebKit

// Scans a printed scorecard when the web app posts { type: "scan" } to the scorecard handler (New course).
// A menu offers Take Photo (the ordinary camera, one photo) or Choose from Photos (up to two pictures, e.g.
// screenshots of holes 1-9 and 10-18 from another golf app). The photo picker needs no access to the library: it
// hands over only the pictures chosen. ScorecardReader then reads the text on the phone: nothing is sent anywhere
// and it works offline. (The document camera was tried first, but it keeps capturing pages until Save.)
// The web app's scorecardScanned() gets { status: "reading" } while it reads, then { status: "ok", pages }, or
// "cancelled", "denied", "unsupported" or "failed", so the course editor stays as it was unless something was read.
final class ScorecardBridge: NSObject, WKScriptMessageHandler, UIImagePickerControllerDelegate,
                             UINavigationControllerDelegate, PHPickerViewControllerDelegate {
    static let handlerName = "scorecard"

    weak var webView: WKWebView?
    private var busy = false

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard !busy else { return }
        guard let webView, let top = webView.topViewController else { reply(["status": "failed"]); return }
        busy = true
        let menu = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            menu.addAction(UIAlertAction(title: "Take Photo", style: .default) { _ in self.takePhoto() })
        }
        menu.addAction(UIAlertAction(title: "Choose from Photos", style: .default) { _ in self.choosePhotos() })
        menu.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in self.reply(["status": "cancelled"]) })
        // An action sheet needs an anchor on iPad; the app is iPhone-only, but it must never crash.
        menu.popoverPresentationController?.sourceView = webView
        menu.popoverPresentationController?.sourceRect = CGRect(x: webView.bounds.midX, y: webView.bounds.maxY, width: 0, height: 0)
        top.present(menu, animated: true)
    }

    // MARK: Camera

    private func takePhoto() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            presentCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { granted ? self.presentCamera() : self.reply(["status": "denied"]) }
            }
        default:
            reply(["status": "denied"])
        }
    }

    private func presentCamera() {
        guard let top = webView?.topViewController else { reply(["status": "failed"]); return }
        let camera = UIImagePickerController()
        camera.sourceType = .camera
        camera.cameraCaptureMode = .photo
        camera.delegate = self
        top.present(camera, animated: true)
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        guard let image = info[.originalImage] as? UIImage else { reply(["status": "failed"]); return }
        read([image])
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        reply(["status": "cancelled"])
    }

    // MARK: Photos

    private func choosePhotos() {
        guard let top = webView?.topViewController else { reply(["status": "failed"]); return }
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 2
        configuration.selection = .ordered
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        top.present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard !results.isEmpty else { reply(["status": "cancelled"]); return }
        // Loaded in the background; kept in the order they were chosen.
        var images = [UIImage?](repeating: nil, count: results.count)
        let group = DispatchGroup()
        for (i, result) in results.enumerated() where result.itemProvider.canLoadObject(ofClass: UIImage.self) {
            group.enter()
            result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                DispatchQueue.main.async { images[i] = object as? UIImage; group.leave() }
            }
        }
        group.notify(queue: .main) {
            let loaded = images.compactMap { $0 }
            if loaded.isEmpty { self.reply(["status": "failed"]) } else { self.read(loaded) }
        }
    }

    // MARK: Reading

    private func read(_ images: [UIImage]) {
        send(["status": "reading"])
        let pictures = images.compactMap { image in image.cgImage.map { ($0, CGImagePropertyOrientation(image.imageOrientation)) } }
        DispatchQueue.global(qos: .userInitiated).async {
            let pages = pictures.map { ScorecardReader.read($0.0, orientation: $0.1) }
            DispatchQueue.main.async { self.reply(pages.isEmpty ? ["status": "failed"] : ["status": "ok", "pages": pages]) }
        }
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
