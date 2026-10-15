import SwiftUI
import WatchKit

// PROTOTYPE. The green page, below the hole screen (swipe up or turn the crown): the distance to the hole, live from
// GPS once the hole is marked, and one button that logs a putt where the watch is, so each putt's length is the
// distance from there to the hole. Without a mark, the page asks to mark the hole first.
struct GreenView: View {
    @EnvironmentObject private var store: WatchStore
    let hole: Int
    @Binding var path: [Route]

    // Below this, GPS can't tell one putt from another; the page says so instead of showing a number.
    static let shortest = 3.0

    var body: some View {
        let putts = store.strokes(on: hole).filter { $0.club == "Putter" }.count
        let locked = store.isLocked(hole)
        VStack(spacing: 6) {
            Text("GREEN · HOLE \(hole)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)

            if store.holePosition(hole) == nil {
                markButton
            } else {
                TimelineView(.periodic(from: .now, by: 2)) { _ in distance }
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

    // "14 m" to the hole, in whole meters; "< 3 m" when closer; a dash without a fix.
    @ViewBuilder private var distance: some View {
        let value: String = {
            guard let mark = store.holePosition(hole), let fix = store.freshFix else { return "–" }
            let m = meters(fix, WatchEvent.Position(lat: mark.lat, lng: mark.lng, acc: mark.acc))
            return m < Self.shortest ? "< 3" : "\(Int(m.rounded()))"
        }()
        VStack(spacing: -4) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(size: 44, weight: .bold, design: .rounded))
                Text("m").font(.system(size: 16, weight: .semibold)).foregroundStyle(.secondary)
            }
            Text("to the hole").font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var markButton: some View {
        Button {
            if store.markHole(hole) { WKInterfaceDevice.current().play(.success) }
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
