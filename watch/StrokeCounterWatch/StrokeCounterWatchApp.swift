import SwiftUI

@main
struct StrokeCounterWatchApp: App {
    @StateObject private var store = WatchStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
    }
}

enum Route: Hashable {
    case clubs
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
            .onChange(of: scenePhase) { _, phase in store.setAppActive(phase != .background) }
            .alert("Update the watch app", isPresented: Binding(get: { store.phoneIsNewer }, set: { store.phoneIsNewer = $0 })) {
                Button("OK") {}
            } message: {
                Text("The iPhone app is newer. Install the latest Stroke Counter on the watch to keep syncing.")
            }
    }

    @ViewBuilder private var content: some View {
        if let hole = store.currentHole {
            NavigationStack(path: $path) {
                ActiveHoleView(hole: hole, path: $path)
                    .navigationDestination(for: Route.self) { route in
                        switch route {
                        case .clubs:
                            ClubPickerView(path: $path)
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
