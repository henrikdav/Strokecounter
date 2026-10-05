import SwiftUI
import WatchKit

// Screen 5: confirms finishing the hole. The phone is told, locks the hole and moves on to the next one.
struct FinishHoleView: View {
    @EnvironmentObject private var store: WatchStore
    let hole: Int
    @Binding var path: [Route]

    var body: some View {
        let count = store.strokes(on: hole).count
        let par = store.hole(hole)?.par
        let last = store.isLastHole(hole)
        VStack(spacing: 6) {
            Text("Hole \(hole) complete")
                .font(.system(size: 16, weight: .bold))
            Text("\(count) \(count == 1 ? "stroke" : "strokes")" + (par.map { " · Par \($0)" } ?? ""))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Button {
                store.finishHole(hole)
                WKInterfaceDevice.current().play(.success)
                path = []
            } label: {
                HStack(spacing: 4) {
                    // The watch never finishes the round itself; that is done on the phone's scorecard.
                    Text(last ? "Finish hole" : "Next hole")
                    if !last { Image(systemName: "chevron.right") }
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(accentInk)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(Capsule().fill(accent))
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            Button("Cancel") { path = [] }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .padding(.horizontal, 8)
        .navigationBarBackButtonHidden(true)
    }
}
