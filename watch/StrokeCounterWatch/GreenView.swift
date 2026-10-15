import SwiftUI
import WatchKit

// The green page, below the hole screen (swipe up or turn the crown): the distance to the hole, live from
// GPS once the hole is marked, and one button that logs a putt where the watch is, so each putt's length is the
// distance from there to the hole. Without a mark, the page asks to mark the hole first; a long press on the
// distance marks it again (the newest mark wins). Marking takes a few seconds standing at the cup, averaged into
// one mark. The distance is only as exact as the GPS (GreenDistance). No confirmation after a putt: a click on
// the wrist, the count goes up, and changes are made on the phone.
struct GreenView: View {
    @EnvironmentObject private var store: WatchStore
    let hole: Int
    @Binding var path: [Route]

    var body: some View {
        let putts = store.strokes(on: hole).filter { $0.club == "Putter" }.count
        let locked = store.isLocked(hole)
        VStack(spacing: 6) {
            Text("GREEN · HOLE \(hole)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)

            if store.markingHole == hole {
                holdStill
            } else if store.holePosition(hole) == nil {
                markButton
            } else {
                TimelineView(.periodic(from: .now, by: 2)) { _ in distance }
                    .contentShape(Rectangle())
                    .onLongPressGesture(minimumDuration: 0.6) { mark() }
                    .accessibilityAction(named: "Mark hole again") { mark() }
            }

            Text("\(putts) \(putts == 1 ? "putt" : "putts")")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Button {
                if store.logStroke(club: "Putter", hole: hole) != nil {
                    WKInterfaceDevice.current().play(.click)
                }
            } label: {
                Text("+1 PUTT")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(accentInk)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: 18).fill(accent))
            }
            .buttonStyle(.plain)
            .disabled(locked)
            .accessibilityLabel("Log putt \(putts + 1)")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(Color(red: 0.04, green: 0.20, blue: 0.10).gradient, for: .tabView)
        // Each page has its own toolbar: Finish hole here too, as putting out is where the hole ends.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    path = [.finish(hole: hole)]
                } label: {
                    Image(systemName: "checkmark")
                }
                .disabled(store.isRoundFinished)
                .accessibilityLabel("Finish hole")
            }
        }
    }

    // "14 m" to the hole; "≈ 14 m", dimmed, when the GPS is poor; "< 3 m" when closer than it can tell; a dash
    // without a fix.
    @ViewBuilder private var distance: some View {
        let mark = store.holePosition(hole).map { WatchEvent.Position(lat: $0.lat, lng: $0.lng, acc: $0.acc) }
        let reading = GreenDistance.reading(mark: mark, now: store.freshFix)
        let (prefix, value, rough): (String, String, Bool) = {
            switch reading {
            case .none: return ("", "–", false)
            case .near(let m): return ("<", "\(m)", false)
            case .meters(let m, let rough): return (rough ? "≈" : "", "\(m)", rough)
            }
        }()
        VStack(spacing: -4) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                if !prefix.isEmpty { Text(prefix).font(.system(size: 28, weight: .semibold, design: .rounded)) }
                Text(value).font(.system(size: 44, weight: .bold, design: .rounded))
                Text("m").font(.system(size: 16, weight: .semibold)).foregroundStyle(.secondary)
            }
            .opacity(rough ? 0.6 : 1)
            Text("to the hole").font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    // Gathers fixes at the cup for a few seconds, then marks it: a tap on the wrist to start, another when done.
    private func mark() {
        WKInterfaceDevice.current().play(.start)
        store.markHoleStandingStill(hole) { marked in
            WKInterfaceDevice.current().play(marked ? .success : .failure)
        }
    }

    private var holdStill: some View {
        VStack(spacing: 4) {
            ProgressView()
            Text("Marking… hold still")
                .font(.system(size: 13, weight: .semibold))
        }
        .frame(maxWidth: .infinity, minHeight: 64)
    }

    private var markButton: some View {
        Button {
            mark()
        } label: {
            VStack(spacing: 2) {
                Label("Mark hole", systemImage: "flag.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text("standing at the cup")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(RoundedRectangle(cornerRadius: 16).fill(tile))
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview("Green, marked") {
    NavigationStack { GreenView(hole: 3, path: .constant([])) }
        .environmentObject(PreviewData.store(PreviewData.round(marked: true)))
}

#Preview("Green, not marked") {
    NavigationStack { GreenView(hole: 3, path: .constant([])) }
        .environmentObject(PreviewData.store())
}
#endif
