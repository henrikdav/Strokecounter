import Foundation

// What the screens use. It ties together the round as shown (RoundState: the phone's snapshot with this watch's
// unconfirmed events on top), the sync with the phone (SyncClient) and what runs during a round (RoundSession:
// workout and GPS), keeps the choices made on the watch, and saves state so it survives a restart.
// The protocol is described in docs/watch-sync.md.
final class WatchStore: ObservableObject {
    @Published private(set) var state: RoundState
    @Published var lastClub: String?
    @Published var armedMods: Set<Modifier> = []
    // A snapshot came from a newer iPhone app than this watch app understands. It is ignored (the round already
    // here keeps working, and events sent from here are still accepted) and the watch asks to be updated.
    @Published var phoneIsNewer = false

    private let sync = SyncClient()
    private let session = RoundSession()
    private let defaults = UserDefaults.standard
    private static var now: Double { (Date().timeIntervalSince1970 * 1000).rounded() }

    init() {
        let snapshot = defaults.data(forKey: "snapshot").flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
        let outbox = defaults.data(forKey: "outbox").flatMap { try? JSONDecoder().decode([WatchEvent].self, from: $0) } ?? []
        state = RoundState(snapshot: snapshot, outbox: outbox)
        lastClub = defaults.string(forKey: "lastClub")
        sync.onSnapshot = { [weak self] json in self?.receive(snapshotJSON: json) }
        sync.outbox = { [weak self] in self?.state.outbox ?? [] }
        session.onLateFix = { [weak self] strokeId, roundId, hole, position in
            self?.change { $0.fillPosition(position, strokeId: strokeId, roundId: roundId, hole: hole) }
        }
        session.roundChanged(id: state.round?.id, finished: state.isRoundFinished)
        sync.activate()
    }

    // MARK: What the screens show

    var round: Snapshot.Round? { state.round }
    var bag: [String] { state.bag }
    var currentHole: Int? { state.currentHole }
    var isRoundFinished: Bool { state.isRoundFinished }
    func hole(_ number: Int) -> Snapshot.Hole? { state.hole(number) }
    func isLastHole(_ number: Int) -> Bool { state.isLastHole(number) }
    func isLocked(_ hole: Int) -> Bool { state.isLocked(hole) }
    func strokes(on hole: Int) -> [Snapshot.Stroke] { state.strokes(on: hole) }

    // The club the next stroke is logged with: the one picked here last, else the phone's.
    var club: String { lastClub ?? state.phoneClub ?? bag.first ?? "Driver" }

    // MARK: Actions

    // Picks the club for the next stroke without logging anything, like arming a modifier.
    func selectClub(_ club: String) {
        lastClub = club
        defaults.set(club, forKey: "lastClub")
    }

    // Logs a stroke with the club and the armed modifiers, which then reset like on the phone. Never waits for
    // GPS: it takes the latest fix if it is recent, otherwise logs now and fills the position in shortly.
    @discardableResult
    func logStroke(club: String, hole: Int) -> Snapshot.Stroke? {
        let fix = session.freshFix
        let id = UUID().uuidString.lowercased()
        guard let event = change({ $0.logStroke(id: id, club: club, mods: armedMods, hole: hole, t: Self.now, position: fix) }),
              let roundId = state.round?.id else { return nil }
        if fix == nil { session.awaitFix(strokeId: id, roundId: roundId, hole: hole) } else { session.stopAwaitingFix() }
        selectClub(club)
        armedMods = []
        return event.stroke
    }

    func removeStroke(_ id: String, hole: Int) {
        change { $0.removeStroke(id: id, hole: hole, t: Self.now) }
    }

    func finishHole(_ hole: Int) {
        change { $0.finishHole(hole, t: Self.now) }
        session.roundChanged(id: state.round?.id, finished: state.isRoundFinished)
    }

    // MARK: Round lifecycle

    // The hole screen is showing: starts the round's workout (and with it GPS) before the first tap.
    func roundScreenShown() {
        session.roundScreenShown()
    }

    func setAppActive(_ active: Bool) {
        session.setAppActive(active)
    }

    // MARK: Sync and storage

    // Applies a change to the round, then saves and sends the event it made, if any.
    @discardableResult
    private func change(_ apply: (inout RoundState) -> WatchEvent?) -> WatchEvent? {
        guard let event = apply(&state) else { return nil }
        saveOutbox()
        sync.send([event])
        return event
    }

    private func receive(snapshotJSON json: String) {
        switch state.receive(snapshotJSON: json) {
        case .applied:
            phoneIsNewer = false
            defaults.set(Data(json.utf8), forKey: "snapshot")
            saveOutbox()
            session.roundChanged(id: state.round?.id, finished: state.isRoundFinished)
        case .newerVersion:
            phoneIsNewer = true
        case .unreadable:
            break
        }
    }

    private func saveOutbox() {
        defaults.set(try? JSONEncoder().encode(state.outbox), forKey: "outbox")
    }
}
