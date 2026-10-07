import SwiftUI
import WatchKit

// Screen 1: the hole being played. The wide "+1 STROKE" button is the only way to log a stroke and says inside it
// exactly what a tap will log (club and armed modifiers); Bag and Modifier only change that selection. Above it,
// the distance of the current shot, live from GPS; a tap locks it as where the shot landed (Stop on the phone).
// Undo (top left) removes the hole's last stroke; finish (top right, or a swipe up) ends the hole.
// A hole locked on the phone shows a notice instead, and only finish works; a round finished on the phone is
// read-only with nothing to do. Both update live with the phone.
struct ActiveHoleView: View {
    @EnvironmentObject private var store: WatchStore
    let hole: Int
    @Binding var path: [Route]

    var body: some View {
        let strokes = store.strokes(on: hole)
        let club = store.club(on: hole)
        let next = strokeSummary(club: club, mods: Array(store.armedMods))
        let locked = store.isLocked(hole)
        let finished = store.isRoundFinished
        VStack(spacing: 5) {
            VStack(spacing: 0) {
                Text("HOLE \(hole)")
                    .font(.system(size: 15, weight: .bold))
                parLine
            }

            // Worded like the phone app's "strokes on this hole"; the count in white so it reads at a glance outdoors.
            (Text("\(strokes.count) \(strokes.count == 1 ? "stroke" : "strokes")").foregroundStyle(.primary)
                + Text(" on this hole").foregroundStyle(.secondary))
                .font(.system(size: 13))

            if locked {
                lockedNotice(finished: finished)
            } else {
                // Re-read every few seconds as well, so a fix that has gone stale clears the distance.
                TimelineView(.periodic(from: .now, by: 5)) { _ in
                    distanceLine(store.shotDistance(on: hole))
                }

                Button {
                    if let stroke = store.logStroke(club: club, hole: hole) {
                        WKInterfaceDevice.current().play(.click)
                        path = [.logged(stroke, number: strokes.count + 1, hole: hole)]
                    }
                } label: {
                    // Shaped like the phone app's "+1 stroke" button, with what the tap will log inside it.
                    VStack(spacing: 1) {
                        Text("+1 STROKE")
                            .font(.system(size: 18, weight: .heavy))
                        Text(next)
                            .font(.system(size: 13, weight: .bold))
                            .opacity(0.75)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(accentInk)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(RoundedRectangle(cornerRadius: 18).fill(accent))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Log stroke \(strokes.count + 1): \(next)")

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
        // Swipe up to finish the hole, as in the mockup. Not on a finished round: nothing can change there.
        .gesture(DragGesture(minimumDistance: 30).onEnded { value in
            if !finished && value.translation.height < -40 && abs(value.translation.width) < abs(value.translation.height) {
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
                .disabled(finished)
                .accessibilityLabel("Finish hole")
            }
        }
    }

    // "PAR 4 · +1": the handicap strokes on the hole, worked out on the phone. Nothing extra when there are none.
    @ViewBuilder private var parLine: some View {
        let par = store.hole(hole)?.par
        let extra = store.extra(hole) ?? 0
        if par != nil || extra != 0 {
            HStack(spacing: 0) {
                if let par { Text("PAR \(par)").foregroundStyle(.primary) }
                if par != nil && extra != 0 { Text(" · ").foregroundStyle(.secondary) }
                if extra != 0 { Text(extra > 0 ? "+\(extra)" : "−\(-extra)").fontWeight(.bold).foregroundStyle(accent) }
            }
            .font(.system(size: 11))
            .accessibilityElement(children: .combine)
        }
    }

    // The current shot's distance: live with a pulsing dot and a stop mark (tap to lock it), grey once locked,
    // and a dash when there is nothing to measure (no stroke, a putt, no position, or no recent GPS fix).
    @ViewBuilder private func distanceLine(_ distance: RoundState.ShotDistance) -> some View {
        switch distance {
        case let .live(value, strokeId):
            Button {
                let locked = store.lockDistance(strokeId: strokeId, hole: hole)
                WKInterfaceDevice.current().play(locked ? .success : .failure)
            } label: {
                distanceContent(value: value, live: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("This shot, \(value) meters. Tap to lock the distance.")
        case let .locked(value):
            distanceContent(value: value, live: false)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("This shot, \(value) meters, locked")
        case .none:
            distanceContent(value: "–", live: false, dim: true)
                .accessibilityHidden(true)
        }
    }

    private func distanceContent(value: String, live: Bool, dim: Bool = false) -> some View {
        HStack(spacing: 6) {
            if live { PulsingDot() }
            Text(value)
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(live ? Color.primary : Color.secondary)
            Text("m · this shot")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
            if live {
                // A stop mark, like the phone's Stop button.
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.secondary)
                    .frame(width: 6, height: 6)
                    .frame(width: 16, height: 16)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary, lineWidth: 1.6))
            }
        }
        .opacity(dim ? 0.45 : 1)
        .padding(.horizontal, 12)
        .frame(minHeight: 34)
        .background(Capsule().fill(tile))
    }

    // Shown in place of "+1 STROKE", the summary and Bag/Modifier. Not a button: there is nothing to do here.
    private func lockedNotice(finished: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: finished ? "flag.checkered" : "lock.fill")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            Text(finished ? "Round finished" : "Hole locked")
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
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(RoundedRectangle(cornerRadius: 12).fill(tile))
        }
        .buttonStyle(.plain)
    }
}

// The live distance's dot, fading in and out.
private struct PulsingDot: View {
    @State private var dim = false

    var body: some View {
        Circle()
            .fill(accent)
            .frame(width: 7, height: 7)
            .opacity(dim ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: dim)
            .onAppear { dim = true }
    }
}
