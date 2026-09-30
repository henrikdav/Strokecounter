import SwiftUI
import WebKit

// Temporary scaffold that shows the bundled web app, only to prove the build pipeline.
// The iOS app is meant to become fully native and drop this view.
struct WebAppView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let gps = context.coordinator.gps
        configuration.userContentController.add(gps, name: GPSBridge.handlerName)
        if let script = GPSBridge.userScript {
            configuration.userContentController.addUserScript(script)
        }
        let webView = WKWebView(frame: .zero, configuration: configuration)
        gps.webView = webView
        webView.uiDelegate = context.coordinator
        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "web") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    // WKWebView shows no JavaScript dialogs on its own: without this, confirm() answers false
    // at once and the web app's delete buttons do nothing.
    final class Coordinator: NSObject, WKUIDelegate {
        let gps = GPSBridge()

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
            present(alert, from: webView, orElse: { completionHandler(false) })
        }

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
            present(alert, from: webView, orElse: completionHandler)
        }

        // WebKit requires the completion handler to be called, so fall back when there is nothing to present on.
        private func present(_ alert: UIAlertController, from webView: WKWebView, orElse fallback: () -> Void) {
            var top = webView.window?.rootViewController
            while let presented = top?.presentedViewController { top = presented }
            guard let top else { fallback(); return }
            top.present(alert, animated: true)
        }
    }
}
