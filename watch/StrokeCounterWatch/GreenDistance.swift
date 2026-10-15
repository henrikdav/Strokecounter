import Foundation

// The distance to the hole on the green page, only as exact as the GPS behind it. Each fix's accuracy (acc) is the
// radius the true position is within about two times in three; the distance rests on two of them, the hole's mark
// and the watch now, so its uncertainty is about √(acc_mark² + acc_now²). Two fixes taken minutes apart on the
// same green share much of their error, which cancels, so that is on the cautious side; the recordings of the next
// rounds tell how much (the marks and every fix are logged).
enum GreenDistance {
    enum Reading: Equatable {
        case none                        // no mark or no fresh fix
        case near(Int)                   // closer than GPS can tell: "< 3 m"
        case meters(Int, rough: Bool)    // "14 m"; rough: GPS is poor, shown as "≈ 14 m"
    }

    // Below this the number is noise even with good GPS.
    static let shortest = 3.0
    // An uncertainty above this makes the number rough (about 6 m each way on both fixes).
    static let roughAbove = 8.0

    static func reading(mark: WatchEvent.Position?, now: WatchEvent.Position?) -> Reading {
        guard let mark, let now else { return .none }
        let distance = meters(now, mark)
        let uncertainty = (mark.acc * mark.acc + now.acc * now.acc).squareRoot()
        // Half the uncertainty, as the shared error cancels; never under 3 m.
        let near = max(shortest, uncertainty / 2)
        if distance < near { return .near(Int(near.rounded(.up))) }
        return .meters(Int(distance.rounded()), rough: uncertainty > roughAbove)
    }

    // MARK: Marking the hole

    // How long the player stands at the cup while the watch gathers fixes for the mark.
    static let markFor: TimeInterval = 4
    // A fix this much worse than the best one gathered is left out.
    static let worseThanBest = 2.0

    // The hole's mark from the fixes gathered while standing at the cup: their mean, each weighted by 1/acc², so a
    // poor fix counts for little and one far worse than the best not at all. The mark keeps the best fix's accuracy:
    // GPS errors drift slowly, so a few seconds of fixes share most of theirs and averaging them is no proof of
    // better. Nil without fixes.
    static func averaged(_ fixes: [WatchEvent.Position]) -> WatchEvent.Position? {
        guard let best = fixes.map(\.acc).filter({ $0 > 0 }).min() else { return nil }
        let used = fixes.filter { $0.acc > 0 && $0.acc <= best * worseThanBest }
        let weights = used.map { 1 / ($0.acc * $0.acc) }
        let total = weights.reduce(0, +)
        let lat = zip(used, weights).map { $0.lat * $1 }.reduce(0, +) / total
        let lng = zip(used, weights).map { $0.lng * $1 }.reduce(0, +) / total
        return WatchEvent.Position(lat: lat, lng: lng, acc: best)
    }
}
