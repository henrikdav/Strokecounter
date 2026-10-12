import SwiftUI

// Sets the lie and shot type of a stroke just logged (opened from its pill on the confirmation screen). Each toggle
// changes the stroke at once; Done goes back to the confirmation, where the choice shows.
struct ModifiersView: View {
    @EnvironmentObject private var store: WatchStore
    let strokeId: String
    let hole: Int
    @Binding var path: [Route]

    var body: some View {
        let stroke = store.strokes(on: hole).first { $0.id == strokeId }
        let mods = Set(stroke?.mods.compactMap(Modifier.init(rawValue:)) ?? [])
        ScrollView {
            VStack(alignment: .leading, spacing: 5) {
                group("LIE", [.rough, .bunker], mods: mods, stroke: stroke)
                group("SHOT", [.chip, .pitch], mods: mods, stroke: stroke)
                    .padding(.top, 6)
                Button {
                    if !path.isEmpty { path.removeLast() }
                } label: {
                    Text("Done")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(accentInk)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(RoundedRectangle(cornerRadius: 12).fill(accent))
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
            }
        }
        .navigationTitle("Lie & shot")
    }

    private func group(_ title: String, _ choices: [Modifier], mods: Set<Modifier>, stroke: Snapshot.Stroke?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            HStack(spacing: 5) {
                ForEach(choices, id: \.self) { mod in
                    let on = mods.contains(mod)
                    Button {
                        guard let stroke else { return }
                        var changed = mods
                        if on { changed.remove(mod) } else { changed.insert(mod) }
                        store.editStroke(strokeId, hole: hole, club: stroke.club, mods: changed)
                    } label: {
                        Text(mod.label)
                            .font(.system(size: 13, weight: on ? .bold : .regular))
                            .foregroundStyle(on ? accent : .primary)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(
                                RoundedRectangle(cornerRadius: 9)
                                    .fill(on ? accent.opacity(0.18) : tile)
                                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(on ? accent : .clear))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }
}

#if DEBUG
#Preview("Lie & shot") {
    NavigationStack { ModifiersView(strokeId: "p2", hole: 3, path: .constant([])) }
        .environmentObject(PreviewData.store())
}
#endif
