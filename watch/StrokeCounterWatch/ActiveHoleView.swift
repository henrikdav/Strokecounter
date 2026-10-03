import SwiftUI
import WatchKit

// Screen 1: the hole being played. The wide "+1 STROKE" button is the only way to log a stroke; the line under
// it says exactly what a tap will log (club and armed modifiers). Bag and Modifier only change that selection.
// Undo (top left) removes the hole's last stroke; finish (top right, or a swipe up) ends the hole.
// A hole locked on the phone shows a notice instead, and only finish works; it updates live with the phone.
struct ActiveHoleView: View {
    @EnvironmentObject private var store: WatchStore
    let hole: Int
    @Binding var path: [Route]

    var body: some View {
        let strokes = store.strokes(on: hole)
        let next = strokeSummary(club: store.club, mods: Array(store.armedMods))
        let locked = store.isLocked(hole)
        VStack(spacing: 6) {
            VStack(spacing: 0) {
                Text("HOLE \(hole)")
                    .font(.system(size: 15, weight: .bold))
                if let par = store.hole(hole)?.par {
                    Text("PAR \(par)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            // Worded like the phone app's "strokes on this hole".
            Text("\(strokes.count) \(strokes.count == 1 ? "stroke" : "strokes") on this hole")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            if locked {
                lockedNotice
            } else {
                Button {
                    if let stroke = store.logStroke(club: store.club, hole: hole) {
                        WKInterfaceDevice.current().play(.click)
                        path = [.logged(stroke, number: strokes.count + 1, hole: hole)]
                    }
                } label: {
                    // Shaped like the phone app's "+1 stroke" button.
                    Text("+1 STROKE")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(accentInk)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(RoundedRectangle(cornerRadius: 18).fill(accent))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Log stroke \(strokes.count + 1): \(next)")

                // What the next tap logs, in the phone's stroke-list shorthand.
                Text(next)
                    .font(.system(size: 20, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityLabel("Next stroke: \(next)")

                HStack(spacing: 4) {
                    navButton("Bag") { path = [.clubs] }
                    navButton("Modifier") { path = [.modifiers] }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        // Starts the round's workout session (and with it GPS) before the first tap, so a position is usually
        // ready when a stroke is logged.
        .onAppear { store.roundScreenShown() }
        // Swipe up to finish the hole, as in the mockup.
        .gesture(DragGesture(minimumDistance: 30).onEnded { value in
            if value.translation.height < -40 && abs(value.translation.width) < abs(value.translation.height) {
                path = [.finish(hole: hole)]
            }
        })
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    if let last = strokes.last {
                        store.removeStroke(last.id, hole: hole)
                        WKInterfaceDevice.current().play(.directionDown)
                    }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(strokes.isEmpty || locked)
                .accessibilityLabel("Undo last stroke")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    path = [.finish(hole: hole)]
                } label: {
                    Image(systemName: "checkmark")
                }
                .accessibilityLabel("Finish hole")
            }
        }
    }

    // Shown in place of "+1 STROKE", the summary and Bag/Modifier. Not a button: there is nothing to do here.
    private var lockedNotice: some View {
        VStack(spacing: 4) {
            Image(systemName: "lock.fill")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            Text("Hole locked")
                .font(.system(size: 18, weight: .bold))
            Text("Unlock on phone to edit")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 118)
        .accessibilityElement(children: .combine)
    }

    private func navButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(RoundedRectangle(cornerRadius: 12).fill(tile))
        }
        .buttonStyle(.plain)
    }
}
