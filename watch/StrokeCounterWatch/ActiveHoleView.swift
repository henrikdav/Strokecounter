import SwiftUI
import WatchKit

// Screen 1: the hole being played, kept simple: the hole, the stroke count, the shot in play and one button. The
// wide "+1 STROKE" logs a stroke with the suggested club (not shown, since it may be wrong); club and modifiers are
// set on the screen that confirms it, and later changes or removals are made on the phone. Above the button, the
// hole's last stroke with its distance, live from GPS; a tap locks the distance where the ball landed. Finish
// (top right) ends the hole. A hole locked on the phone shows a notice instead, and only finish works; a round
// finished on the phone is read-only with nothing to do. Both update live with the phone.
struct ActiveHoleView: View {
    @EnvironmentObject private var store: WatchStore
    let hole: Int
    @Binding var path: [Route]

    var body: some View {
        let strokes = store.strokes(on: hole)
        let club = store.club(on: hole)
        let locked = store.isLocked(hole)
        let finished = store.isRoundFinished
        VStack(spacing: 6) {
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
                if let last = strokes.last {
                    // Re-read every few seconds as well, so a fix that has gone stale clears the distance.
                    TimelineView(.periodic(from: .now, by: 5)) { _ in
                        shotPill(last, store.shotDistance(on: hole))
                    }
                }

                Button {
                    if let stroke = store.logStroke(club: club, hole: hole) {
                        WKInterfaceDevice.current().play(.click)
                        path = [.logged(stroke, number: strokes.count + 1, hole: hole)]
                    }
                } label: {
                    // Shaped like the phone app's "+1 stroke" button.
                    Text("+1 STROKE")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(accentInk)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: 18).fill(accent))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Log stroke \(strokes.count + 1)")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        // Starts the round's workout session (and with it GPS) before the first tap, so a position is usually
        // ready when a stroke is logged.
        .onAppear { store.roundScreenShown() }
        .toolbar {
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

    // The shot in play: the hole's last stroke ("7i · Rough") with its distance below, live while walking with a
    // pulsing dot and a stop mark. A tap locks the distance where the watch is now, as where the ball landed (Stop
    // on the phone); it is grey and fixed after that. Only information otherwise: strokes are changed right after
    // logging, or on the phone. No distance row for a putt, a penalty stroke or a stroke without a position; a dash
    // while there is no recent GPS fix.
    @ViewBuilder private func shotPill(_ stroke: Snapshot.Stroke, _ distance: RoundState.ShotDistance) -> some View {
        let summary = strokeSummary(club: stroke.club, mods: stroke.mods.compactMap(Modifier.init(rawValue:)))
            + (stroke.auto == true ? " · auto" : "")   // logged by the watch itself, not yet confirmed
        switch distance {
        case let .live(value, strokeId):
            Button {
                let locked = store.lockDistance(strokeId: strokeId, hole: hole)
                WKInterfaceDevice.current().play(locked ? .success : .failure)
            } label: {
                pill(summary) { distanceRow(value, live: true) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(summary), \(value) meters. Tap to lock the distance where the ball landed.")
        case let .locked(value):
            pill(summary) { distanceRow(value, live: false) }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(summary), \(value) meters, locked")
        case .none:
            if stroke.isMeasured && stroke.position != nil {
                pill(summary) { distanceRow("–", live: false).opacity(0.45) }   // waiting for a GPS fix
                    .accessibilityElement(children: .combine)
            } else {
                pill(summary) { EmptyView() }
                    .accessibilityElement(children: .combine)
            }
        }
    }

    private func pill<Distance: View>(_ summary: String, @ViewBuilder distance: () -> Distance) -> some View {
        VStack(spacing: 1) {
            Text(summary)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
            distance()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: 50)
        .fixedSize(horizontal: false, vertical: true)   // never squeezed by the rows around it
        .background(RoundedRectangle(cornerRadius: 17).fill(tile))
    }

    private func distanceRow(_ value: String, live: Bool) -> some View {
        HStack(spacing: 6) {
            if live { PulsingDot() }
            Text(value)
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(live ? Color.primary : Color.secondary)
            Text("m")
                .font(.system(size: 12, weight: .bold))
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

#if DEBUG
#Preview("Hole with strokes") {
    NavigationStack { ActiveHoleView(hole: 3, path: .constant([])) }
        .environmentObject(PreviewData.store())
}

#Preview("First stroke") {
    NavigationStack { ActiveHoleView(hole: 3, path: .constant([])) }
        .environmentObject(PreviewData.store(PreviewData.round(strokesOnHole3: 0)))
}

#Preview("No GPS") {
    NavigationStack { ActiveHoleView(hole: 3, path: .constant([])) }
        .environmentObject(PreviewData.store(fix: nil))
}

#Preview("Locked on the phone") {
    NavigationStack { ActiveHoleView(hole: 3, path: .constant([])) }
        .environmentObject(PreviewData.store(PreviewData.round(locked: [1, 2, 3])))
}

#Preview("Round finished") {
    NavigationStack { ActiveHoleView(hole: 3, path: .constant([])) }
        .environmentObject(PreviewData.store(PreviewData.round(locked: Array(1...9), finished: true)))
}
#endif
