import SwiftUI

// Changes the club of a stroke just logged (opened from its pill on the confirmation screen): the bag from the
// phone, the stroke's club picked and in view. A tap sets it and goes back to the confirmation.
struct ClubPickerView: View {
    @EnvironmentObject private var store: WatchStore
    let strokeId: String
    let hole: Int
    @Binding var path: [Route]

    var body: some View {
        let stroke = store.strokes(on: hole).first { $0.id == strokeId }
        let current = stroke?.club ?? ""
        ScrollViewReader { proxy in
            List {
                Section {
                    ForEach(store.bag, id: \.self) { club in
                        Button {
                            if let stroke, club != stroke.club {
                                store.editStroke(strokeId, hole: hole, club: club,
                                                 mods: Set(stroke.mods.compactMap(Modifier.init(rawValue:))))
                            }
                            if !path.isEmpty { path.removeLast() }
                        } label: {
                            HStack {
                                Text(club)
                                    .font(.system(size: 15, weight: club == current ? .bold : .regular))
                                Spacer()
                                if club == current {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(accent)
                                }
                            }
                            .padding(.vertical, -4)
                        }
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 9)
                                .fill(club == current ? accent.opacity(0.18) : tile)
                                .overlay(RoundedRectangle(cornerRadius: 9).stroke(club == current ? accent : .clear))
                        )
                        .id(club)
                    }
                } header: {
                    Text("\(store.bag.count) clubs")
                }
            }
            // Compact rows, as in the mockup, so more of the bag fits between Crown turns.
            .environment(\.defaultMinListRowHeight, 34)
            .task {
                // Wait one layout pass; scrolling before the list has its rows does nothing.
                try? await Task.sleep(for: .milliseconds(50))
                proxy.scrollTo(current, anchor: .center)
            }
        }
        .navigationTitle("Club")
    }
}

#if DEBUG
#Preview("Club") {
    NavigationStack { ClubPickerView(strokeId: "p2", hole: 3, path: .constant([])) }
        .environmentObject(PreviewData.store())
}
#endif
