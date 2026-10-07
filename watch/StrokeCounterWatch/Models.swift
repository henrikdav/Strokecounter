import Foundation

// The round as the phone last sent it (see sendWatchSnapshot in web/index.html). The phone owns it.
// Sync protocol version (docs/watch-sync.md). Raised only for a change an older app could misread; new optional
// fields keep it, since both sides ignore fields they don't know.
enum WatchProtocol {
    static let version = 2   // 2: the watch also sends .mark and .landing
}

struct Snapshot: Codable, Equatable {
    struct Hole: Codable, Equatable {
        let number: Int
        let par: Int?
        let index: Int?
        var extra: Int? = nil              // handicap strokes on this hole, worked out on the phone; nil without handicap
        var position: HolePosition? = nil  // where the hole (cup) was marked, on either device
        var teeClub: String? = nil         // the likely tee club from the phone's history; nil without history
    }

    struct HolePosition: Codable, Equatable {
        let lat: Double
        let lng: Double
        let acc: Double
        let t: Double   // when it was marked (ms); the newest mark wins
    }

    struct Stroke: Codable, Equatable, Hashable {
        let id: String
        let club: String
        let mods: [String]
        let t: Double   // milliseconds since 1970, as in the web app
        // Where the stroke was played from, when there was a GPS fix (accuracy in meters).
        var lat: Double? = nil
        var lng: Double? = nil
        var acc: Double? = nil
        var landing: WatchEvent.Position? = nil   // where the shot landed, when its distance was locked

        var position: WatchEvent.Position? {
            guard let lat, let lng else { return nil }
            return WatchEvent.Position(lat: lat, lng: lng, acc: acc ?? 0)
        }

        // Putts and penalty strokes get no shot distance, as on the phone (shotDistance in web/index.html).
        var isMeasured: Bool { club != "Putter" && club != "Penalty" }
    }

    struct Round: Codable, Equatable {
        let id: String
        let name: String
        let holes: [Hole]
        let currentHole: Int
        let locked: [Int]
        let strokes: [String: [Stroke]]   // keyed by hole number
        let removed: [String]
        var finished: Bool? = nil          // finished on the phone's scorecard; missing from older phone versions
    }

    var v: Int? = nil   // missing in snapshots from before versioning, which count as 1
    let round: Round?
    let bag: [String]
    let club: String
}

// Something done on the watch, sent to the phone and kept until a snapshot shows the phone has it
// (see applyWatchEvents in web/index.html).
struct WatchEvent: Codable, Equatable {
    enum Kind: String, Codable { case add, remove, finish, position, landing, mark }

    struct Position: Codable, Equatable, Hashable {
        let lat: Double
        let lng: Double
        let acc: Double
    }

    var v: Int? = WatchProtocol.version   // optional so an outbox saved before versioning still loads
    let type: Kind
    let roundId: String
    let hole: Int
    var stroke: Snapshot.Stroke? = nil   // add
    var id: String? = nil                // remove, position, landing: the stroke
    var position: Position? = nil        // position: a late fix for the stroke; landing: where it landed; mark: the hole
    var t: Double? = nil                 // remove, finish, landing, mark: when it was done (ms), judged against locks

    // True once the snapshot shows the phone has applied this event.
    func isConfirmed(by round: Snapshot.Round) -> Bool {
        switch type {
        case .add:
            guard let stroke else { return true }
            return round.removed.contains(stroke.id) ||
                (round.strokes[String(hole)] ?? []).contains { $0.id == stroke.id }
        case .remove:
            // Applied, or refused because the hole is locked on the phone.
            return (id.map(round.removed.contains) ?? true) || round.locked.contains(hole)
        case .finish:
            return round.locked.contains(hole)
        case .position:
            guard let id else { return true }
            return round.removed.contains(id) ||
                (round.strokes[String(hole)] ?? []).contains { $0.id == id && $0.lat != nil }
        case .landing:
            // Applied, refused because the hole is locked, or the stroke is gone.
            guard let id else { return true }
            return round.removed.contains(id) || round.locked.contains(hole) ||
                (round.strokes[String(hole)] ?? []).contains { $0.id == id && $0.landing != nil }
        case .mark:
            // Applied or overtaken by a newer mark, or refused because the hole is locked.
            let marked = round.holes.first { $0.number == hole }?.position
            return round.locked.contains(hole) || (marked.map { $0.t >= (t ?? 0) } ?? false)
        }
    }
}

// The four modifiers, in the web app's order and with its keys.
enum Modifier: String, CaseIterable {
    case chip, pitch, bunker, rough

    var label: String { rawValue.capitalized }
}

// Great-circle distance in meters (haversine), the same formula as meters() in web/index.html, so a distance on the
// watch matches the one the phone works out from the same positions.
func meters(_ a: WatchEvent.Position, _ b: WatchEvent.Position) -> Double {
    let r = 6_371_000.0, rad = Double.pi / 180
    let dLat = (b.lat - a.lat) * rad, dLng = (b.lng - a.lng) * rad
    let h = pow(sin(dLat / 2), 2) + cos(a.lat * rad) * cos(b.lat * rad) * pow(sin(dLng / 2), 2)
    return 2 * r * asin(sqrt(h))
}

// A distance as the phone shows it (fmtDist): whole meters, "<1" below one, "≈ " when the two positions together
// are less accurate than 25 m.
func formatDistance(_ m: Double, approx: Bool) -> String {
    let rounded = Int(m.rounded())
    return (approx ? "≈ " : "") + (rounded < 1 ? "<1" : String(rounded))
}

// A stroke in the phone's shorthand: the club, then its modifiers in the phone's order, e.g. "PW · Chip".
func strokeSummary(club: String, mods: [Modifier]) -> String {
    ([club] + Modifier.allCases.filter(mods.contains).map(\.label)).joined(separator: " · ")
}
