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
    // The recording being written now, never sent while it grows.
    var activeRecording: () -> URL? = { nil }

    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil
    private var resentRecordings = false

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

    // Swing detection step 1: sends a finished recording's files to the phone. The system queues them and
    // delivers them when it can; each file is deleted here once delivered (didFinish below).
    func sendRecording(_ folder: URL) {
        guard let session, session.activationState == .activated else { return }
        let sending = Set(session.outstandingFileTransfers.map(\.file.fileURL.standardizedFileURL))
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for file in files where !sending.contains(file.standardizedFileURL) {
            session.transferFile(file, metadata: ["recording": folder.lastPathComponent, "file": file.lastPathComponent])
        }
    }

    // Recordings left from an earlier run (not delivered before the app was closed) are sent again. Called once
    // the session is ready, before a new recording can start.
    private func resendRecordings() {
        let folders = (try? FileManager.default.contentsOfDirectory(at: SwingRecorder.recordingsFolder, includingPropertiesForKeys: nil)) ?? []
        let active = activeRecording()?.standardizedFileURL
        folders.filter { $0.standardizedFileURL != active }.forEach(sendRecording)
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        guard error == nil else { return }
        let file = fileTransfer.file.fileURL
        try? FileManager.default.removeItem(at: file)
        let folder = file.deletingLastPathComponent()
        if (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.isEmpty == true {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    static func encode(_ events: [WatchEvent]) -> String? {
        (try? JSONEncoder().encode(events)).flatMap { String(data: $0, encoding: .utf8) }
    }

    // Asks the phone for its current round instead of waiting for the application context, which can be slow
    // or missing (for example right after this app was installed). Wakes the phone app if needed.
    func requestSnapshot() {
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
            if !self.resentRecordings { self.resentRecordings = true; self.resendRecordings() }
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
