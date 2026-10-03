import SwiftUI

// Screen 2: the bag from the phone. A tap selects the club for the next stroke and goes back to the hole;
// nothing is logged here (like the Modifiers screen).
struct ClubPickerView: View {
    @EnvironmentObject private var store: WatchStore
    @Binding var path: [Route]

    var body: some View {
        let current = store.club
        ScrollViewReader { proxy in
            List {
                Section {
                    ForEach(store.bag, id: \.self) { club in
                        Button {
                            store.selectClub(club)
                            path = []
                        } label: {
                            HStack {
                                Text(club)
                                    .font(.system(size: 15, weight: club == current ? .bold : .regular))
                                Spacer()
                                if club == current {
                                    Text("SELECTED")
                                        .font(.system(size: 9, weight: .semibold))
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
        .navigationTitle("My bag")
    }
}
