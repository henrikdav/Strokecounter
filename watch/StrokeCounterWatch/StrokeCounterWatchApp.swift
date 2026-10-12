import HealthKit
import SwiftUI
import WatchKit

@main
struct StrokeCounterWatchApp: App {
    @WKApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(delegate.store)
        }
    }
}

// Owns the store, so it exists before watchOS hands over a workout from the iPhone, which can come before any view.
final class AppDelegate: NSObject, WKApplicationDelegate {
    let store = WatchStore()

    // The iPhone app started a round and launched this app (HKHealthStore.startWatchApp in WatchBridge.swift).
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        store.startedFromPhone()
    }
}

enum Route: Hashable {
    case clubs
    case swingClubs
    case modifiers
    case logged(Snapshot.Stroke, number: Int, hole: Int)
    case finish(hole: Int)
}

let accent = Color(red: 0.19, green: 0.82, blue: 0.35)        // #30D158, as in the mockup
let accentInk = Color(red: 0.02, green: 0.14, blue: 0.06)     // dark text on the accent
let tile = Color(white: 0.11)                                  // #1C1C1E

struct RootView: View {
    @EnvironmentObject private var store: WatchStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [Route] = []

    var body: some View {
        content
            .onChange(of: scenePhase) { _, phase in
                store.setAppActive(phase != .background)
                if phase == .active { showSwingClubs() }
            }
            // A swing found while the screen is up (the wrist was not lowered) shows the list at once.
            .onChange(of: store.swingTime) { _, _ in if scenePhase == .active { showSwingClubs() } }
            .alert("Update the watch app", isPresented: Binding(get: { store.phoneIsNewer }, set: { store.phoneIsNewer = $0 })) {
                Button("OK") {}
            } message: {
                Text("The iPhone app is newer. Install the latest Stroke Counter on the watch to keep syncing.")
            }
    }

    // Raising the wrist within a minute of a swing shows the club list to log it; after that, or once it is used,
    // the list goes and the hole screen shows as usual.
    private func showSwingClubs() {
        guard let hole = store.currentHole else { return }
        if store.swingWaiting(on: hole) {
            if path.last != .swingClubs {
                path = [.swingClubs]
                store.swingListShown()
            }
        } else if path.last == .swingClubs {
            path = []
        }
    }

    @ViewBuilder private var content: some View {
        if let hole = store.currentHole {
            NavigationStack(path: $path) {
                ActiveHoleView(hole: hole, path: $path)
                    .navigationDestination(for: Route.self) { route in
                        switch route {
                        case .clubs:
                            ClubPickerView(hole: hole, path: $path)
                        case .swingClubs:
                            SwingClubsView(hole: hole, path: $path)
                        case .modifiers:
                            ModifiersView(path: $path)
                        case let .logged(stroke, number, hole):
                            StrokeLoggedView(stroke: stroke, number: number, hole: hole, path: $path)
                        case let .finish(hole):
                            FinishHoleView(hole: hole, path: $path)
                        }
                    }
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "iphone")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Start a round on your iPhone")
                    .font(.headline)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }
}

#if DEBUG
#Preview("No round") {
    RootView()
        .environmentObject(PreviewData.store(nil))
}

#Preview("Round") {
    RootView()
        .environmentObject(PreviewData.store())
}
#endif
