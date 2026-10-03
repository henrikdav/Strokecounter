import SwiftUI

// Screen 4: confirms the stroke and returns to the hole after 1.5 s, or at once on a tap. Undo removes it.
struct StrokeLoggedView: View {
    @EnvironmentObject private var store: WatchStore
    let stroke: Snapshot.Stroke
    let number: Int
    let hole: Int
    @Binding var path: [Route]

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(accentInk)
                .frame(width: 54, height: 54)
                .background(Circle().fill(accent))
            VStack(spacing: 2) {
                Text("Stroke \(number) logged")
                    .font(.system(size: 16, weight: .bold))
                Text(strokeSummary(club: stroke.club, mods: stroke.mods.compactMap(Modifier.init(rawValue:))))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Undo") {
                store.removeStroke(stroke.id, hole: hole)
                path = []
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { path = [] }
        .navigationBarBackButtonHidden(true)
        .task {
            try? await Task.sleep(for: .seconds(1.5))
            // Only if this screen is still showing; Undo or a tap may already have left it.
            if case .logged(let shown, _, _) = path.last, shown.id == stroke.id { path = [] }
        }
    }
}
