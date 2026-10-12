import SwiftUI

// Screen 4: confirms the stroke just logged, and is where it is described. Two pills, like the shot distance on the
// hole screen: the club, and the modifiers (lie and shot); each opens its screen and the choice shows here at once.
// Undo removes the stroke. Goes back to the hole after a few seconds, or at once on a tap elsewhere; the countdown
// pauses while the club or modifier screen is open and starts again on return. Also opened from the hole screen's
// "Last:" line, to change the hole's last stroke later.
struct StrokeLoggedView: View {
    @EnvironmentObject private var store: WatchStore
    let stroke: Snapshot.Stroke
    let number: Int
    let hole: Int
    @Binding var path: [Route]

    static let shownFor: Duration = .seconds(5)

    var body: some View {
        // The stroke as it is now, with changes made on the club and modifier screens.
        let current = store.strokes(on: hole).first { $0.id == stroke.id } ?? stroke
        let mods = current.mods.compactMap(Modifier.init(rawValue:))
        let editable = !store.isLocked(hole)
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(accentInk)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(accent))
                Text("Stroke \(number) logged")
                    .font(.system(size: 15, weight: .bold))
            }
            pill(current.club, placeholder: false, enabled: editable) {
                path.append(.editClub(strokeId: stroke.id, hole: hole))
            }
            .accessibilityLabel("Club, \(current.club). Change")
            pill(mods.isEmpty ? "+ Lie / shot" : Modifier.allCases.filter(mods.contains).map(\.label).joined(separator: " · "),
                 placeholder: mods.isEmpty, enabled: editable && current.club != "Penalty") {
                path.append(.editModifiers(strokeId: stroke.id, hole: hole))
            }
            .accessibilityLabel(mods.isEmpty ? "No lie or shot type. Add" : "Lie and shot. Change")
            Button("Undo") {
                store.removeStroke(stroke.id, hole: hole)
                path = []
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!editable)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { path = [] }
        .navigationBarBackButtonHidden(true)
        // Runs again whenever this screen is on top: opened, or back from the club or modifier screen.
        .task(id: isOnTop) {
            guard isOnTop else { return }
            try? await Task.sleep(for: Self.shownFor)
            if isOnTop { path = [] }
        }
    }

    private var isOnTop: Bool {
        if case .logged(let shown, _, _) = path.last { return shown.id == stroke.id }
        return false
    }

    private func pill(_ text: String, placeholder: Bool, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(placeholder ? .secondary : .primary)
                if enabled {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 16, weight: .semibold))
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(Capsule().fill(tile))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

#if DEBUG
#Preview("Stroke logged") {
    NavigationStack { StrokeLoggedView(stroke: PreviewData.loggedStroke, number: 2, hole: 3, path: .constant([])) }
        .environmentObject(PreviewData.store())
}

#Preview("No modifiers yet") {
    NavigationStack { StrokeLoggedView(stroke: PreviewData.round().round!.strokes["3"]![0], number: 1, hole: 3, path: .constant([])) }
        .environmentObject(PreviewData.store())
}
#endif
