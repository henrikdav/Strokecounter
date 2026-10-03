import SwiftUI

@main
struct StrokeCounterApp: App {
    init() {
        // Start the watch connection at launch, also when the watch wakes this app in the background.
        _ = WatchBridge.shared
    }

    var body: some Scene {
        WindowGroup {
            WebAppView()
                .ignoresSafeArea()
        }
    }
}
