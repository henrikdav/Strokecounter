import SwiftUI
import WatchKit

// Shown when the wrist is raised within a minute of a swing (swing detection). The heading stays at the top and
// "Not a shot" in the bottom bar; between them the bag scrolls, with the suggested club picked and in view. A tap
// on a club logs the stroke at once, with the swing's position; lie and shot are set on the confirmation that
// follows, as after +1. "Not a shot" (a practice swing) logs nothing and is the only way out, so the watch knows
// the swing was not a shot: no back button.
struct SwingClubsView: View {
    @EnvironmentObject private var store: WatchStore
    let hole: Int
    @Binding var path: [Route]

    var body: some View {
        let suggested = store.club(on: hole)
        VStack(spacing: 4) {
            VStack(spacing: 0) {
                Text("Swing detected")
                    .font(.system(size: 15, weight: .bold))
                Text("Tap the club to log")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            ScrollViewReader { proxy in
                List {
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
                }
                .environment(\.defaultMinListRowHeight, 34)
                .task {
                    try? await Task.sleep(for: .milliseconds(50))
                    proxy.scrollTo(suggested, anchor: .center)
                }
            }
            Button {
                store.dismissSwing()
                path = []
            } label: {
                Text("Not a shot")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .background(Capsule().fill(Color(white: 0.2)))
            }
            .buttonStyle(.plain)
            // Inset from the sides, so the display's rounded corners don't cut it at the bottom edge.
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
        }
        // Down to the bottom edge, so the list gets the room the bottom margin would take.
        .ignoresSafeArea(edges: .bottom)
        .navigationBarBackButtonHidden(true)
    }
}

#if DEBUG
#Preview("After a swing") {
    NavigationStack { SwingClubsView(hole: 3, path: .constant([])) }
        .environmentObject(PreviewData.store())
}
#endif
