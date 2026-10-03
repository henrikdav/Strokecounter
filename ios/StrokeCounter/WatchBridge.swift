import UIKit
import WatchConnectivity
import WebKit

// Connects the web app's round to the Apple Watch app.
//
// Phone → watch: the web app posts { type: "snapshot", json } when it starts and whenever it saves. The latest one
// is saved here and goes to the watch as the application context (only the latest matters) and, when the watch
// app is running, also as a live message, since the context alone can be slow or lost. It is sent again once the
// session is ready or the watch app gets installed, and the watch can ask for it ("snapshot-request"), which also
// works when the watch wakes this app in the background before the web app has loaded.
// Watch → phone: the watch sends events (stroke added or removed, hole finished) with transferUserInfo, which
// the system queues and delivers even while this app is in the background. They are kept in a file here until
// the web app has applied them, then removed. Applying is idempotent, so a repeat delivery does no harm.
// When the app comes to the foreground it also asks the watch to resend anything the phone has not confirmed.
final class WatchBridge: NSObject, WKScriptMessageHandler, WCSessionDelegate {
    static let handlerName = "watch"
    static let shared = WatchBridge()

    weak var webView: WKWebView?
    private var webReady = false
    private var delivering = false
    private var lastSnapshot = UserDefaults.standard.string(forKey: "watchSnapshot")
    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil
    private let pendingURL = URL.applicationSupportDirectory.appending(path: "watch-pending.json")

    private override init() {
        super.init()
        session?.delegate = self
        session?.activate()
        NotificationCenter.default.addObserver(self, selector: #selector(willEnterForeground),
                                               name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    // MARK: Web app → native

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "hello":
            // The page has (re)loaded: hand it anything that arrived while it was not running.
            webReady = true
            deliverPending()
        case "snapshot":
            guard let json = body["json"] as? String else { return }
            lastSnapshot = json
            UserDefaults.standard.set(json, forKey: "watchSnapshot")
            pushSnapshot()
        default:
            break
        }
    }

    private func pushSnapshot() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let json = lastSnapshot, let session, session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled else { return }
        try? session.updateApplicationContext(["snapshot": json])
        if session.isReachable {
            session.sendMessage(["snapshot": json], replyHandler: nil, errorHandler: nil)
        }
    }

    // MARK: Watch → native

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        receive(userInfo)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receive(message)
    }

    // The watch asks for the current round, e.g. right after its app starts.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        DispatchQueue.main.async {
            if message["type"] as? String == "snapshot-request", let json = self.lastSnapshot {
                replyHandler(["snapshot": json])
            } else {
                replyHandler([:])
            }
        }
    }

    private func receive(_ payload: [String: Any]) {
        guard let json = payload["events"] as? String,
              let events = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [Any], !events.isEmpty else { return }
        DispatchQueue.main.async {
            self.savePending(self.loadPending() + events)
            self.deliverPending()
        }
    }

    @objc private func willEnterForeground() {
        deliverPending()
        askWatchToResend()
    }

    // The watch answers with every event the phone has not yet confirmed in a snapshot.
    private func askWatchToResend() {
        guard let session, session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(["type": "flush"], replyHandler: { [weak self] reply in
            self?.receive(reply)
        }, errorHandler: nil)
    }

    // MARK: Pending events

    private func deliverPending() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard webReady, !delivering, let webView else { return }
        let events = loadPending()
        guard !events.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: events),
              let json = String(data: data, encoding: .utf8) else { return }
        delivering = true
        webView.evaluateJavaScript("applyWatchEvents(\(json))") { [weak self] result, _ in
            guard let self else { return }
            self.delivering = false
            // Only drop what the page confirmed; events that arrived meanwhile stay for the next round.
            guard result as? Bool == true else { return }
            self.savePending(Array(self.loadPending().dropFirst(events.count)))
            self.deliverPending()
        }
    }

    private func loadPending() -> [Any] {
        guard let data = try? Data(contentsOf: pendingURL),
              let events = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
        return events
    }

    private func savePending(_ events: [Any]) {
        try? FileManager.default.createDirectory(at: pendingURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: events) {
            try? data.write(to: pendingURL, options: .atomic)
        }
    }

    // MARK: Session lifecycle

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.pushSnapshot()
            self.askWatchToResend()
        }
    }

    // The watch app was installed (or the watch changed): it has no round yet, so send the current one.
    func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.pushSnapshot() }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    // After switching to another watch, activate again so the new one can connect.
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        if session.isReachable {
            DispatchQueue.main.async {
                self.pushSnapshot()
                self.askWatchToResend()
            }
        }
    }
}
