import CoreLocation
import CoreMotion
import Foundation
import WatchKit

// Follows the watch's motion while the round's golf workout runs: Core Motion's device motion at 50 Hz goes
// through the SwingDetector, and each swing found is passed on (onSwing). It also records the round
// (recordsEvents): events.jsonl with a header, each swing found, every stroke logged on the watch and how, the GPS
// fixes and the battery level every minute; and, when collecting data to tune the detector (recordsMotion),
// motion.bin with every sample. When the workout ends, the files go to the phone (WatchBridge saves them under
// Documents/SwingRecordings) and are deleted here once delivered.
//
// motion.bin: one 40-byte record per sample, little-endian Float32 × 10: seconds since the header's t0, user
// acceleration x y z (g), rotation rate x y z (rad/s), gravity x y z (g).
final class SwingRecorder {
    // The events of every round with a running workout, to follow the detector and the battery.
    static let recordsEvents = true
    // Every motion sample too: only when collecting data to tune the detector. Off since 2026-10-14, when the
    // detector had five rounds of data and the battery use (about 20 % an hour) was the thing to cut.
    static let recordsMotion = false
    // 50 Hz: on the recorded rounds the detector found 20 of 27 shots at 50 Hz against 21 at 100 Hz, for half the
    // work (battery).
    static let rate = 50.0

    // A swing was found: when (seconds since 1970) and how strong. Called on the main queue.
    var onSwing: ((Date, SwingDetector.Swing) -> Void)?
    // A finished recording: the folder with events.jsonl (and motion.bin when recorded).
    var onFinished: ((URL) -> Void)?

    private let motion = CMMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
        return queue
    }()
    private var detector = SwingDetector()   // used on the motion queue only
    private(set) var isRunning = false
    private var folder: URL?
    private var motionFile: FileHandle?
    private var eventsFile: FileHandle?
    private var buffer = Data()
    private var batteryTimer: Timer?
    private var t0: TimeInterval = 0          // seconds since 1970 at the start
    private var bootOffset: TimeInterval = 0  // seconds since 1970 at the device's boot, for motion timestamps

    var currentFolder: URL? { folder }

    static var recordingsFolder: URL { URL.documentsDirectory.appending(path: "SwingRecordings") }

    // Starts the round's recording (events and battery), and reads the motion sensor if detecting is on.
    func start(roundId: String, detecting: Bool) {
        guard !isRunning else { return }
        isRunning = true
        let now = Date().timeIntervalSince1970
        t0 = now
        bootOffset = now - ProcessInfo.processInfo.systemUptime
        if Self.recordsEvents {
            openFiles(roundId: roundId, now: now, detecting: detecting)
            startBatteryLog()
        }
        setDetecting(detecting)
    }

    // Swing detection on or off (the phone's Settings), also mid-round: off stops reading the motion sensor, which
    // is what costs battery; the recording goes on, noting when it changed, so the battery can be compared.
    func setDetecting(_ on: Bool) {
        guard isRunning, motion.isDeviceMotionAvailable, on != motion.isDeviceMotionActive else { return }
        if on {
            motion.deviceMotionUpdateInterval = 1 / Self.rate
            queue.addOperation { [self] in detector = SwingDetector() }
            motion.startDeviceMotionUpdates(to: queue) { [weak self] sample, _ in
                guard let self, let sample else { return }
                self.handle(sample)
            }
        } else {
            motion.stopDeviceMotionUpdates()
        }
        write(event: ["type": "detection", "t": Self.ms(Date()), "on": on])
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        motion.stopDeviceMotionUpdates()
        queue.addOperation { [self] in
            flush()
            try? motionFile?.close()
            motionFile = nil
        }
        queue.waitUntilAllOperationsAreFinished()
        batteryTimer?.invalidate()
        batteryTimer = nil
        guard let folder else { return }
        noteBattery()
        write(event: ["type": "stop", "t": Self.ms(Date())])
        try? eventsFile?.close()
        eventsFile = nil
        self.folder = nil
        onFinished?(folder)
    }

    // MARK: Events for the recording

    func noteSwing(at time: Date, _ swing: SwingDetector.Swing, position: WatchEvent.Position?) {
        var event: [String: Any] = ["type": "swing", "t": Self.ms(time), "rotation": swing.rotation, "impact": swing.impact]
        if let position { event["lat"] = position.lat; event["lng"] = position.lng; event["acc"] = position.acc }
        write(event: event)
    }

    // A stroke logged on the watch, and whether from the club list shown after a swing and with the swing's position.
    func noteStroke(_ stroke: Snapshot.Stroke, hole: Int, fromSwingList: Bool, swingPosition: Bool) {
        write(event: ["type": "stroke", "t": stroke.t, "id": stroke.id, "club": stroke.club, "mods": stroke.mods, "hole": hole,
                      "fromSwingList": fromSwingList, "swingPosition": swingPosition, "auto": stroke.auto == true])
    }

    func noteEdit(strokeId: String, club: String, mods: [String]) {
        write(event: ["type": "edit", "t": Self.ms(Date()), "id": strokeId, "club": club, "mods": mods])
    }

    func noteRemoved(strokeId: String) {
        write(event: ["type": "remove", "t": Self.ms(Date()), "id": strokeId])
    }

    // The club list was shown after a swing, or the player said it was not a shot.
    func note(_ type: String) {
        write(event: ["type": type, "t": Self.ms(Date())])
    }

    func noteFix(_ fix: CLLocation) {
        write(event: ["type": "fix", "t": Self.ms(fix.timestamp),
                      "lat": fix.coordinate.latitude, "lng": fix.coordinate.longitude,
                      "acc": fix.horizontalAccuracy, "speed": fix.speed])
    }

    // The hole marked on the green page: the mark, and how many fixes it was averaged from and how far apart they were.
    func noteHoleMark(hole: Int, mark: WatchEvent.Position, fixes: [WatchEvent.Position]) {
        write(event: ["type": "hole-mark", "t": Self.ms(Date()), "hole": hole, "lat": mark.lat, "lng": mark.lng, "acc": mark.acc,
                      "fixes": fixes.count, "spread": fixes.map { meters($0, mark) }.max() ?? 0])
    }

    // The battery level now and every minute, to measure what a round costs.
    private func startBatteryLog() {
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
        noteBattery()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.noteBattery() }
        RunLoop.main.add(timer, forMode: .common)
        batteryTimer = timer
    }

    private func noteBattery() {
        let device = WKInterfaceDevice.current()
        let state: String
        switch device.batteryState {
        case .charging: state = "charging"
        case .full: state = "full"
        case .unplugged: state = "unplugged"
        default: state = "unknown"
        }
        write(event: ["type": "battery", "t": Self.ms(Date()), "level": Double(device.batteryLevel), "state": state])
    }

    // MARK: Motion

    private func handle(_ sample: CMDeviceMotion) {
        let a = sample.userAcceleration, r = sample.rotationRate, g = sample.gravity
        let t = bootOffset + sample.timestamp
        if let swing = detector.add(t: t, rotation: (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot(),
                                    acceleration: (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()) {
            DispatchQueue.main.async { self.onSwing?(Date(timeIntervalSince1970: swing.t), swing) }
        }
        guard motionFile != nil else { return }
        let values: [Float32] = [Float32(t - t0),
                                 Float32(a.x), Float32(a.y), Float32(a.z),
                                 Float32(r.x), Float32(r.y), Float32(r.z),
                                 Float32(g.x), Float32(g.y), Float32(g.z)]
        values.withUnsafeBytes { buffer.append(contentsOf: $0) }
        if buffer.count >= 40 * 200 { flush() }   // about every two seconds
    }

    // MARK: Files

    private func openFiles(roundId: String, now: TimeInterval, detecting: Bool) {
        let folder = Self.recordingsFolder.appending(path: "\(Self.stamp(now))-\(roundId.prefix(8))")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if Self.recordsMotion {
                FileManager.default.createFile(atPath: folder.appending(path: "motion.bin").path, contents: nil)
                motionFile = try FileHandle(forWritingTo: folder.appending(path: "motion.bin"))
            }
            FileManager.default.createFile(atPath: folder.appending(path: "events.jsonl").path, contents: nil)
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
            "model": Self.model, "os": device.systemVersion,
            "detector": ["minRotation": SwingDetector.minRotation, "minImpact": SwingDetector.minImpact],
            "motion": Self.recordsMotion, "detecting": detecting
        ])
    }

    private func flush() {
        guard !buffer.isEmpty else { return }
        try? motionFile?.write(contentsOf: buffer)
        buffer.removeAll(keepingCapacity: true)
    }

    private func write(event: [String: Any]) {
        guard let eventsFile, var line = try? JSONSerialization.data(withJSONObject: event) else { return }
        line.append(0x0A)
        try? eventsFile.write(contentsOf: line)
    }

    private static func ms(_ date: Date) -> Double { (date.timeIntervalSince1970 * 1000).rounded() }

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
