import Foundation

// The round as the phone last sent it (see sendWatchSnapshot in web/index.html). The phone owns it.
struct Snapshot: Codable, Equatable {
    struct Hole: Codable, Equatable {
        let number: Int
        let par: Int?
        let index: Int?
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

    let round: Round?
    let bag: [String]
    let club: String
}

// Something done on the watch, sent to the phone and kept until a snapshot shows the phone has it
// (see applyWatchEvents in web/index.html).
struct WatchEvent: Codable, Equatable {
    enum Kind: String, Codable { case add, remove, finish, position }

    struct Position: Codable, Equatable {
        let lat: Double
        let lng: Double
        let acc: Double
    }

    let type: Kind
    let roundId: String
    let hole: Int
    var stroke: Snapshot.Stroke? = nil   // add
    var id: String? = nil                // remove, position
    var position: Position? = nil        // position: a fix that arrived just after the stroke was logged
    var t: Double? = nil                 // remove, finish: when it was done (ms), so the phone can judge it against a hole lock

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
        }
    }
}

// The four modifiers, in the web app's order and with its keys.
enum Modifier: String, CaseIterable {
    case chip, pitch, bunker, rough

    var label: String { rawValue.capitalized }
}

// A stroke in the phone's shorthand: the club, then its modifiers in the phone's order, e.g. "PW · Chip".
func strokeSummary(club: String, mods: [Modifier]) -> String {
    ([club] + Modifier.allCases.filter(mods.contains).map(\.label)).joined(separator: " · ")
}
