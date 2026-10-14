import SwiftUI
import WatchKit

// Shown when the wrist is raised within a minute of a swing, or after walking away from one without logging it
// (swing detection): the club list (ClubListView) with
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
        // A swing walked away from shows when it was, so it reads as a stroke from a while ago.
        .navigationTitle(title)
    }

    private var title: String {
        guard let time = store.swingToLogTime, -time.timeIntervalSinceNow > RoundSession.swingWindow else { return "Swing detected" }
        return "Swing at " + time.formatted(date: .omitted, time: .shortened)
    }
}

#if DEBUG
#Preview("After a swing") {
    NavigationStack { SwingClubsView(hole: 3, path: .constant([])) }
        .environmentObject(PreviewData.store())
}
#endif
