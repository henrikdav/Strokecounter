import SwiftUI
import WatchKit

// Screen 5: confirms finishing the hole. The phone is told, locks the hole and moves on to the next one.
// Mark hole saves where the hole is (standing at the flag), like Mark hole on the phone; the button turns into the
// confirmation in place and can be tapped again to mark anew.
struct FinishHoleView: View {
    @EnvironmentObject private var store: WatchStore
    let hole: Int
    @Binding var path: [Route]
    @State private var noFix = false

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
            // A stroke the watch logged by itself and nobody confirmed: shown before the hole locks.
            ForEach(Array(store.strokes(on: hole).enumerated()).filter { $0.element.auto == true }, id: \.element.id) { index, stroke in
                Text("Stroke \(index + 1) (\(stroke.club)) auto-added")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
                    .multilineTextAlignment(.center)
            }
            if !store.isLocked(hole) {
                markButton
            }
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
        // A swing walked away from and never logged is the hole's last full shot: log it now.
        .onAppear { if !store.isLocked(hole) { store.logForgottenSwing(on: hole) } }
    }

    private var markButton: some View {
        let marked = store.holePosition(hole)
        return Button {
            if store.markHole(hole) {
                noFix = false
                WKInterfaceDevice.current().play(.success)
            } else {
                // No recent GPS fix: say so for a moment instead of doing nothing.
                noFix = true
                WKInterfaceDevice.current().play(.failure)
                Task { try? await Task.sleep(for: .seconds(2)); noFix = false }
            }
        } label: {
            HStack(spacing: 5) {
                if noFix {
                    Text("No GPS fix")
                } else if let marked {
                    Image(systemName: "checkmark")
                    Text("Hole marked · ±\(Int(marked.acc.rounded())) m")
                } else {
                    Image(systemName: "flag")
                    Text("Mark hole")
                }
            }
            .font(.system(size: 13, weight: marked != nil && !noFix ? .bold : .regular))
            .foregroundStyle(marked != nil && !noFix ? accentInk : .primary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(
                Capsule().fill(marked != nil && !noFix ? accent : .clear)
                    .overlay(Capsule().stroke(marked != nil && !noFix ? .clear : Color(white: 0.23)))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(marked.map { "Hole marked, plus or minus \(Int($0.acc.rounded())) meters. Tap to mark again" } ?? "Mark hole position")
    }
}

#if DEBUG
#Preview("Finish hole") {
    NavigationStack { FinishHoleView(hole: 3, path: .constant([])) }
        .environmentObject(PreviewData.store())
}

#Preview("Hole marked") {
    NavigationStack { FinishHoleView(hole: 3, path: .constant([])) }
        .environmentObject(PreviewData.store(PreviewData.round(marked: true)))
}

#Preview("Last hole") {
    NavigationStack { FinishHoleView(hole: 9, path: .constant([])) }
        .environmentObject(PreviewData.store(PreviewData.round(currentHole: 9, locked: Array(1...8))))
}
#endif
