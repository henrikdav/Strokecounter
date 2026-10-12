import SwiftUI
import WatchKit

// Shown when the wrist is raised within a minute of a swing (swing detection): the club list (ClubListView) with
// the suggested club marked. Done logs the stroke with the marked club and the swing's position; lie and shot are
// set on the confirmation that follows, as after +1. Cancel logs nothing and the list doesn't come back for this
// swing, which still gives its position to a stroke logged with +1 within the minute.
struct SwingClubsView: View {
    @EnvironmentObject private var store: WatchStore
    let hole: Int
    @Binding var path: [Route]

    var body: some View {
        ClubListView(clubs: store.bag, start: store.club(on: hole)) { club in
            let number = store.strokes(on: hole).count + 1
            if let stroke = store.logStroke(club: club, hole: hole, fromSwingList: true) {
                WKInterfaceDevice.current().play(.click)
                path = [.logged(stroke, number: number, hole: hole)]
            }
        } onCancel: {
            store.cancelSwingList()
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
