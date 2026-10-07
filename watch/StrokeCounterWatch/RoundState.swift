import Foundation

// The round as the watch shows it: the phone's snapshot with this watch's unconfirmed events (the outbox) on top,
// so a stroke appears at once even when the phone is out of reach. Pure values, no WatchConnectivity, GPS or
// storage, so every rule here is unit-tested (StrokeCounterWatchTests). The protocol is in docs/watch-sync.md.
struct RoundState: Equatable {
    private(set) var snapshot: Snapshot?
    private(set) var outbox: [WatchEvent] = []

    init(snapshot: Snapshot? = nil, outbox: [WatchEvent] = []) {
        self.snapshot = snapshot
        self.outbox = outbox
    }

    // MARK: What the screens show

    var round: Snapshot.Round? { snapshot?.round }

    var bag: [String] { snapshot?.bag ?? [] }

    // The club selected on the phone, used until one is picked on the watch.
    var phoneClub: String? { snapshot?.club }

    // The round is over when it is finished on the phone's scorecard. Only the phone finishes (and unlocks) a
    // round; finishing the last hole does not. A finished round arrives with every hole locked, so it is read-only.
    var isRoundFinished: Bool { round?.finished == true }

    // The hole to play: the phone's current hole, or the one after a hole finished here and not yet confirmed.
    var currentHole: Int? {
        guard let round else { return nil }
        let finished = outbox.filter { $0.type == .finish && $0.roundId == round.id }.map(\.hole)
        guard let last = finished.max() else { return round.currentHole }
        let lastHole = round.holes.last?.number ?? last
        return max(round.currentHole, min(last + 1, lastHole))
    }

    func hole(_ number: Int) -> Snapshot.Hole? {
        round?.holes.first { $0.number == number }
    }

    func isLastHole(_ number: Int) -> Bool {
        round?.holes.last?.number == number
    }

    // A locked hole takes no strokes and no removals. Locked on the phone, or finished here and not yet confirmed.
    // The phone enforces the same rule when the events arrive (applyWatchEvents in web/index.html).
    func isLocked(_ hole: Int) -> Bool {
        guard let round else { return false }
        return round.locked.contains(hole) ||
            outbox.contains { $0.type == .finish && $0.roundId == round.id && $0.hole == hole }
    }

    // The phone's strokes for the hole, minus strokes removed here, plus strokes added here, in playing order.
    func strokes(on hole: Int) -> [Snapshot.Stroke] {
        guard let round else { return [] }
        let mine = outbox.filter { $0.roundId == round.id && $0.hole == hole }
        let removed = Set(mine.compactMap(\.id)).union(round.removed)
        var list = (round.strokes[String(hole)] ?? []).filter { !removed.contains($0.id) }
        for event in mine where event.type == .add {
            if let stroke = event.stroke, !removed.contains(stroke.id), !list.contains(where: { $0.id == stroke.id }) {
                list.append(stroke)
            }
        }
        return list.sorted { $0.t < $1.t }
    }

    // MARK: Changes made on the watch
    // Each one puts its event in the outbox and returns it for sending, or returns nil when it is not allowed.
    // The id, time and position are passed in, so the rules can be tested without a clock or GPS.

    mutating func logStroke(id: String, club: String, mods: Set<Modifier>, hole: Int, t: Double,
                            position: WatchEvent.Position?) -> WatchEvent? {
        guard let round, !isLocked(hole) else { return nil }
        let stroke = Snapshot.Stroke(id: id, club: club, mods: Modifier.allCases.filter(mods.contains).map(\.rawValue),
                                     t: t, lat: position?.lat, lng: position?.lng, acc: position?.acc)
        return queue(WatchEvent(type: .add, roundId: round.id, hole: hole, stroke: stroke))
    }

    mutating func removeStroke(id: String, hole: Int, t: Double) -> WatchEvent? {
        guard let round, !isLocked(hole) else { return nil }
        return queue(WatchEvent(type: .remove, roundId: round.id, hole: hole, id: id, t: t))
    }

    mutating func finishHole(_ hole: Int, t: Double) -> WatchEvent? {
        guard let round else { return nil }
        return queue(WatchEvent(type: .finish, roundId: round.id, hole: hole, t: t))
    }

    // A fix that arrived just after a stroke was logged without one. It also goes on the queued add, so a resend
    // carries it too. Nil when the stroke is no longer there (removed, or another round).
    mutating func fillPosition(_ position: WatchEvent.Position, strokeId: String, roundId: String, hole: Int) -> WatchEvent? {
        guard round?.id == roundId, strokes(on: hole).contains(where: { $0.id == strokeId }) else { return nil }
        if let i = outbox.firstIndex(where: { $0.type == .add && $0.stroke?.id == strokeId }) {
            outbox[i].stroke?.lat = position.lat
            outbox[i].stroke?.lng = position.lng
            outbox[i].stroke?.acc = position.acc
        }
        return queue(WatchEvent(type: .position, roundId: roundId, hole: hole, id: strokeId, position: position))
    }

    private mutating func queue(_ event: WatchEvent) -> WatchEvent {
        outbox.append(event)
        return event
    }

    // MARK: Snapshots from the phone

    enum Received: Equatable {
        case applied
        case newerVersion   // from a newer iPhone app: ignored, the round already here keeps working
        case unreadable
    }

    // A new snapshot. Events it confirms are dropped from the outbox, and so are events for a round the phone no
    // longer shows (those were already queued for delivery when they were made).
    mutating func receive(snapshotJSON json: String) -> Received {
        guard let new = try? JSONDecoder().decode(Snapshot.self, from: Data(json.utf8)) else { return .unreadable }
        guard (new.v ?? 1) <= WatchProtocol.version else { return .newerVersion }
        snapshot = new
        if let round = new.round {
            outbox.removeAll { $0.roundId != round.id || $0.isConfirmed(by: round) }
        } else {
            outbox.removeAll()
        }
        return .applied
    }
}
