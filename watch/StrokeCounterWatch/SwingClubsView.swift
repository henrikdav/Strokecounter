import SwiftUI
import WatchKit

// Shown when the wrist is raised within a minute of a swing (swing detection): the modifiers in one row, then the
// bag with the suggested club picked and in view. Unlike the Bag screen, a tap on a club logs the stroke at once,
// with the swing's position. "Not a shot" (a practice swing) and Back log nothing.
struct SwingClubsView: View {
    @EnvironmentObject private var store: WatchStore
    let hole: Int
    @Binding var path: [Route]

    var body: some View {
        let suggested = store.club(on: hole)
        ScrollViewReader { proxy in
            List {
                Section {
                    HStack(spacing: 4) {
                        ForEach(Modifier.allCases, id: \.self) { mod in modifier(mod) }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 2, bottom: 0, trailing: 2))
                }
                Section {
                    ForEach(store.bag, id: \.self) { club in
                        Button {
                            let number = store.strokes(on: hole).count + 1
                            if let stroke = store.logStroke(club: club, hole: hole, fromSwingList: true) {
                                WKInterfaceDevice.current().play(.click)
                                path = [.logged(stroke, number: number, hole: hole)]
                            }
                        } label: {
                            Text(club)
                                .font(.system(size: 15, weight: club == suggested ? .bold : .regular))
                                .padding(.vertical, -4)
                        }
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 9)
                                .fill(club == suggested ? accent.opacity(0.18) : tile)
                                .overlay(RoundedRectangle(cornerRadius: 9).stroke(club == suggested ? accent : .clear))
                        )
                        .id(club)
                    }
                } header: {
                    Text("Tap the club to log")
                }
                Section {
                    Button {
                        store.dismissSwing()
                        path = []
                    } label: {
                        Text("Not a shot")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .listRowBackground(RoundedRectangle(cornerRadius: 9).fill(tile))
                }
            }
            .environment(\.defaultMinListRowHeight, 34)
            .task {
                try? await Task.sleep(for: .milliseconds(50))
                proxy.scrollTo(suggested, anchor: .center)
            }
        }
        .navigationTitle("Swing")
    }

    // A compact toggle, armed for the stroke like on the Modifiers screen.
    private func modifier(_ mod: Modifier) -> some View {
        let on = store.armedMods.contains(mod)
        return Button {
            if on { store.armedMods.remove(mod) } else { store.armedMods.insert(mod) }
        } label: {
            Text(mod.label)
                .font(.system(size: 10, weight: on ? .bold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(on ? accent : .primary)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(on ? accent.opacity(0.18) : tile)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? accent : .clear))
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

#if DEBUG
#Preview("After a swing") {
    NavigationStack { SwingClubsView(hole: 3, path: .constant([])) }
        .environmentObject(PreviewData.store())
}
#endif
