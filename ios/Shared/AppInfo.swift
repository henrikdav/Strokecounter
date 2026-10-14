import Foundation

// This app's version, build and commit, stamped into Info.plist from git at build time (ios/stamp-build.sh). The
// watch reports its own to the phone, which shows both in Settings, so a watch left on another build is seen.
enum AppInfo {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?" }
    static var commit: String { Bundle.main.object(forInfoDictionaryKey: "StrokeCounterCommit") as? String ?? "" }

    static var dictionary: [String: String] { ["version": version, "build": build, "commit": commit] }
}
