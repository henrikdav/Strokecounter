import SwiftUI

// Screen 3: arms modifiers for the next stroke. Nothing is logged here; Done goes back to the hole.
struct ModifiersView: View {
    @EnvironmentObject private var store: WatchStore
    @Binding var path: [Route]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 5) {
                group("LIE", [.rough, .bunker])
                group("SHOT", [.chip, .pitch])
                    .padding(.top, 6)
                Button {
                    path = []
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
        .navigationTitle("Modifiers")
    }

    private func group(_ title: String, _ mods: [Modifier]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            HStack(spacing: 5) {
                ForEach(mods, id: \.self) { mod in
                    let on = store.armedMods.contains(mod)
                    Button {
                        if on { store.armedMods.remove(mod) } else { store.armedMods.insert(mod) }
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
