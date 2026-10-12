import SwiftUI
import WatchKit

// Shown when the wrist is raised within a minute of a swing (swing detection): the bag with the suggested club
// picked and in view. A tap on a club logs the stroke at once, with the swing's position; lie and shot are set on
// the confirmation that follows, as after +1. "Not a shot" (a practice swing) and Back log nothing.
struct SwingClubsView: View {
    @EnvironmentObject private var store: WatchStore
    let hole: Int
    @Binding var path: [Route]

    var body: some View {
        let suggested = store.club(on: hole)
        ScrollViewReader { proxy in
            List {
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

}

#if DEBUG
#Preview("After a swing") {
    NavigationStack { SwingClubsView(hole: 3, path: .constant([])) }
        .environmentObject(PreviewData.store())
}
#endif
