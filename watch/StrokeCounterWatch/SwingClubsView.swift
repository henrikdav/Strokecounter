import SwiftUI
import WatchKit

// Shown when the wrist is raised within a minute of a swing (swing detection): the club list (ClubListView) with
// the suggested club marked. A tap on a club logs the stroke at once, with the swing's position; lie and shot are
// set on the confirmation that follows, as after +1. "Not a shot" (a practice swing) logs nothing and is the only
// way out, so the watch knows the swing was not a shot.
struct SwingClubsView: View {
    @EnvironmentObject private var store: WatchStore
    let hole: Int
    @Binding var path: [Route]

    var body: some View {
        ClubListView(clubs: store.bag, start: store.club(on: hole), bottomLabel: "Not a shot") { club in
            let number = store.strokes(on: hole).count + 1
            if let stroke = store.logStroke(club: club, hole: hole, fromSwingList: true) {
                WKInterfaceDevice.current().play(.click)
                path = [.logged(stroke, number: number, hole: hole)]
            }
        } onBottom: {
            store.dismissSwing()
            path = []
        }
        .navigationTitle("Swing detected")
    }
}

#if DEBUG
#Preview("After a swing") {
    NavigationStack { SwingClubsView(hole: 3, path: .constant([])) }
        .environmentObject(PreviewData.store())
}
#endif
