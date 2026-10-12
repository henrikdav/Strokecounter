import SwiftUI

// Changes the club of a stroke just logged (opened from its pill on the confirmation screen): the club list
// (ClubListView) with the stroke's club marked. A tap sets it and goes back to the confirmation; Cancel keeps it.
struct ClubPickerView: View {
    @EnvironmentObject private var store: WatchStore
    let strokeId: String
    let hole: Int
    @Binding var path: [Route]

    var body: some View {
        let strokes = store.strokes(on: hole)
        let index = strokes.firstIndex { $0.id == strokeId }
        let stroke = index.map { strokes[$0] }
        ClubListView(clubs: store.bag, start: stroke?.club ?? "", bottomLabel: "Cancel") { club in
            if let stroke, club != stroke.club {
                store.editStroke(strokeId, hole: hole, club: club, mods: Set(stroke.mods.compactMap(Modifier.init(rawValue:))))
            }
            back()
        } onBottom: {
            back()
        }
        .navigationTitle(index.map { "Stroke \($0 + 1)" } ?? "Club")
    }

    private func back() {
        if !path.isEmpty { path.removeLast() }
    }
}

#if DEBUG
#Preview("Club") {
    NavigationStack { ClubPickerView(strokeId: "p2", hole: 3, path: .constant([])) }
        .environmentObject(PreviewData.store())
}
#endif
