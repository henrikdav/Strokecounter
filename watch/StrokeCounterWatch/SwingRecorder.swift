import CoreLocation
import CoreMotion
import Foundation
import WatchKit

// Swing detection, step 1 (test build): records the watch's motion through a round so a swing detector can be
// built from real data. While the round's golf workout runs, Core Motion's device motion is written at 100 Hz to
// motion.bin; events.jsonl gets a header, every stroke logged on the watch (the answer key: the player logs each
// shot right after hitting it) and the GPS fixes. When the workout ends, the two files go to the phone
// (WatchBridge saves them under Documents/SwingRecordings) and are deleted here once delivered.
//
// motion.bin: one 40-byte record per sample, little-endian Float32 × 10: seconds since the header's t0, user
// acceleration x y z (g), rotation rate x y z (rad/s), gravity x y z (g).
final class SwingRecorder {
    // Step 1 only: every round with a running workout is recorded. Remove with step 2.
    static let enabled = true
    static let rate = 100.0

    // A finished recording: the folder with motion.bin and events.jsonl.
    var onFinished: ((URL) -> Void)?

    private let motion = CMMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
        return queue
    }()
    private var folder: URL?
    private var motionFile: FileHandle?
    private var eventsFile: FileHandle?
    private var buffer = Data()
    private var t0: TimeInterval = 0          // seconds since 1970 at the start
    private var bootOffset: TimeInterval = 0  // seconds since 1970 at the device's boot, for motion timestamps

    var isRecording: Bool { folder != nil }
    var currentFolder: URL? { folder }

    static var recordingsFolder: URL { URL.documentsDirectory.appending(path: "SwingRecordings") }

    func start(roundId: String) {
        guard Self.enabled, !isRecording, motion.isDeviceMotionAvailable else { return }
        let now = Date().timeIntervalSince1970
        t0 = now
        bootOffset = now - ProcessInfo.processInfo.systemUptime
        let name = "\(Self.stamp(now))-\(roundId.prefix(8))"
        let folder = Self.recordingsFolder.appending(path: name)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: folder.appending(path: "motion.bin").path, contents: nil)
            FileManager.default.createFile(atPath: folder.appending(path: "events.jsonl").path, contents: nil)
            motionFile = try FileHandle(forWritingTo: folder.appending(path: "motion.bin"))
            eventsFile = try FileHandle(forWritingTo: folder.appending(path: "events.jsonl"))
        } catch {
            return
        }
        self.folder = folder
        let device = WKInterfaceDevice.current()
        write(event: [
            "type": "start", "t0": (now * 1000).rounded(), "roundId": roundId, "rate": Self.rate,
            "wrist": device.wristLocation == .left ? "left" : "right",
            "crown": device.crownOrientation == .left ? "left" : "right",
            "model": Self.model, "os": device.systemVersion
        ])
        motion.deviceMotionUpdateInterval = 1 / Self.rate
        motion.startDeviceMotionUpdates(to: queue) { [weak self] sample, _ in
            guard let self, let sample else { return }
            self.append(sample)
        }
    }

    func stop() {
        guard let folder else { return }
        motion.stopDeviceMotionUpdates()
        queue.addOperation { [self] in
            flush()
            try? motionFile?.close()
            motionFile = nil
        }
        queue.waitUntilAllOperationsAreFinished()
        write(event: ["type": "stop", "t": (Date().timeIntervalSince1970 * 1000).rounded()])
        try? eventsFile?.close()
        eventsFile = nil
        self.folder = nil
        onFinished?(folder)
    }

    // A stroke logged on the watch: the answer key for when a real shot was played.
    func noteStroke(_ stroke: Snapshot.Stroke, hole: Int) {
        write(event: ["type": "stroke", "t": stroke.t, "id": stroke.id, "club": stroke.club, "mods": stroke.mods, "hole": hole])
    }

    func noteRemoved(strokeId: String) {
        write(event: ["type": "remove", "t": (Date().timeIntervalSince1970 * 1000).rounded(), "id": strokeId])
    }

    func noteFix(_ fix: CLLocation) {
        write(event: ["type": "fix", "t": (fix.timestamp.timeIntervalSince1970 * 1000).rounded(),
                      "lat": fix.coordinate.latitude, "lng": fix.coordinate.longitude,
                      "acc": fix.horizontalAccuracy, "speed": fix.speed])
    }

    // MARK: Writing

    private func append(_ sample: CMDeviceMotion) {
        let a = sample.userAcceleration, r = sample.rotationRate, g = sample.gravity
        let values: [Float32] = [Float32(bootOffset + sample.timestamp - t0),
                                 Float32(a.x), Float32(a.y), Float32(a.z),
                                 Float32(r.x), Float32(r.y), Float32(r.z),
                                 Float32(g.x), Float32(g.y), Float32(g.z)]
        values.withUnsafeBytes { buffer.append(contentsOf: $0) }
        if buffer.count >= 40 * 200 { flush() }   // about every two seconds
    }

    private func flush() {
        guard !buffer.isEmpty else { return }
        try? motionFile?.write(contentsOf: buffer)
        buffer.removeAll(keepingCapacity: true)
    }

    private func write(event: [String: Any]) {
        guard isRecording || event["type"] as? String == "stop", let eventsFile,
              var line = try? JSONSerialization.data(withJSONObject: event) else { return }
        line.append(0x0A)
        try? eventsFile.write(contentsOf: line)
    }

    private static func stamp(_ t: TimeInterval) -> String {
        let format = DateFormatter()
        format.dateFormat = "yyyyMMdd-HHmmss"
        format.locale = Locale(identifier: "en_US_POSIX")
        return format.string(from: Date(timeIntervalSince1970: t))
    }

    private static var model: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}
