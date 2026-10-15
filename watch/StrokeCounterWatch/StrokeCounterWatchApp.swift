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
    case swingClubs
    case editClub(strokeId: String, hole: Int)
    case editModifiers(strokeId: String, hole: Int)
    case logged(Snapshot.Stroke, number: Int, hole: Int)
    case finish(hole: Int)
}

let accent = Color(red: 0.19, green: 0.82, blue: 0.35)        // #30D158, as in the mockup
let accentInk = Color(red: 0.02, green: 0.14, blue: 0.06)     // dark text on the accent
let tile = Color(white: 0.11)                                  // #1C1C1E
let penaltyRed = Color(red: 0.77, green: 0.22, blue: 0.18)     // the phone's --flag (#C4372D), for Penalty

struct RootView: View {
    @EnvironmentObject private var store: WatchStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [Route] = []

    var body: some View {
        content
            .onChange(of: scenePhase) { _, phase in
                store.setAppActive(phase != .background)
                if phase == .active { showPending() }
            }
            // A swing found, or walked away from, while the screen is up shows the list at once.
            .onChange(of: store.swingChanges) { _, _ in if scenePhase == .active { showPending() } }
            // Back on the hole screen (e.g. Done on an automatic stroke): what else is waiting comes next.
            .onChange(of: path) { _, now in if now.isEmpty && scenePhase == .active { showPending() } }
            .alert("Update the watch app", isPresented: Binding(get: { store.phoneIsNewer }, set: { store.phoneIsNewer = $0 })) {
                Button("OK") {}
            } message: {
                Text("The iPhone app is newer. Install the latest Stroke Counter on the watch to keep syncing.")
            }
    }

    // Raising the wrist within a minute of a swing shows the club list to log it; after that, or once it is used,
    // the list goes and the hole screen shows as usual.
    // What waits for the wrist raise, in order: a stroke the watch logged by itself (to confirm or fix), then the
    // club list for a swing.
    private func showPending() {
        guard let hole = store.currentHole else { return }
        if path.isEmpty, let auto = store.autoStrokeToShow {
            store.autoStrokeToShow = nil
            if auto.hole == hole, let index = store.strokes(on: hole).firstIndex(where: { $0.id == auto.stroke.id }) {
                path = [.logged(auto.stroke, number: index + 1, hole: hole)]
                return
            }
        }
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
                        case .swingClubs:
                            SwingClubsView(hole: hole, path: $path)
                        case let .editClub(strokeId, hole):
                            ClubPickerView(strokeId: strokeId, hole: hole, path: $path)
                        case let .editModifiers(strokeId, hole):
                            ModifiersView(strokeId: strokeId, hole: hole, path: $path)
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
