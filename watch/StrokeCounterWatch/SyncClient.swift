import Foundation
import WatchConnectivity

// The watch's side of WatchConnectivity (docs/watch-sync.md). It only moves messages: snapshots from the phone
// arrive through onSnapshot, whichever channel brought them, and events go out both queued (transferUserInfo,
// delivered even if the phone app is in the background or closed) and live (sendMessage, when the phone app runs,
// so they show up within a second; the phone ignores the second copy). Callbacks run on the main queue.
final class SyncClient: NSObject, WCSessionDelegate {
    var onSnapshot: ((String) -> Void)?
    // The unconfirmed events, resent when the session is ready and when the phone asks for them ("flush").
    var outbox: () -> [WatchEvent] = { [] }

    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil

    func activate() {
        session?.delegate = self
        session?.activate()
    }

    func send(_ events: [WatchEvent]) {
        guard let session, session.activationState == .activated, !events.isEmpty, let json = Self.encode(events) else { return }
        session.transferUserInfo(["events": json])
        if session.isReachable {
            session.sendMessage(["events": json], replyHandler: nil, errorHandler: nil)
        }
    }

    static func encode(_ events: [WatchEvent]) -> String? {
        (try? JSONEncoder().encode(events)).flatMap { String(data: $0, encoding: .utf8) }
    }

    // Asks the phone for its current round instead of waiting for the application context, which can be slow
    // or missing (for example right after this app was installed). Wakes the phone app if needed.
    private func requestSnapshot() {
        guard let session, session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(["type": "snapshot-request"], replyHandler: { [weak self] reply in
            guard let json = reply["snapshot"] as? String else { return }
            DispatchQueue.main.async { self?.onSnapshot?(json) }
        }, errorHandler: nil)
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            if let json = session.receivedApplicationContext["snapshot"] as? String { self.onSnapshot?(json) }
            self.requestSnapshot()
            // Anything made before the session was ready goes now; the phone ignores repeats.
            self.send(self.outbox())
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        DispatchQueue.main.async { self.requestSnapshot() }
    }

    // A live copy of the snapshot, sent while this app is running.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let json = message["snapshot"] as? String else { return }
        DispatchQueue.main.async { self.onSnapshot?(json) }
    }

    func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        guard let json = context["snapshot"] as? String else { return }
        DispatchQueue.main.async { self.onSnapshot?(json) }
    }

    // The phone came to the foreground and asks for everything it has not confirmed yet.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        DispatchQueue.main.async {
            replyHandler(["events": Self.encode(self.outbox()) ?? "[]"])
        }
    }
}
