import XCTest
@testable import StrokeCounterWatch

// The watch's round logic: what is shown when the phone's snapshot and the watch's own unconfirmed events meet,
// what the watch refuses, and when an event counts as confirmed (docs/watch-sync.md, "Rules on the watch").
final class RoundStateTests: XCTestCase {

    // MARK: Test data

    // A snapshot as the phone sends it: nine par 4s, round "r", strokes keyed by hole number.
    private func snapshotJSON(roundId: String? = "r", currentHole: Int = 1, locked: [Int] = [], finished: Bool? = nil,
                              strokes: [Int: [[String: Any]]] = [:], removed: [String] = [], v: Int? = 2,
                              extra: [Int: Int] = [:], marked: [Int: [String: Double]] = [:],
                              bag: [String] = ["Driver", "7i", "Putter"], pars: [Int: Int] = [:], tee: [Int: String] = [:]) -> String {
        var snapshot: [String: Any] = ["bag": bag, "club": "7i"]
        if let v { snapshot["v"] = v }
        if let roundId {
            var round: [String: Any] = [
                "id": roundId, "name": "Test", "currentHole": currentHole, "locked": locked, "removed": removed,
                "holes": (1...9).map { n -> [String: Any] in
                    var hole: [String: Any] = ["number": n, "par": pars[n] ?? 4, "index": n]
                    if let club = tee[n] { hole["teeClub"] = club }
                    if let e = extra[n] { hole["extra"] = e }
                    if let m = marked[n] { hole["position"] = m }
                    return hole
                },
                "strokes": Dictionary(uniqueKeysWithValues: strokes.map { (String($0.key), $0.value) })
            ]
            if let finished { round["finished"] = finished }
            snapshot["round"] = round
        } else {
            snapshot["round"] = NSNull()
        }
        let data = try! JSONSerialization.data(withJSONObject: snapshot)
        return String(data: data, encoding: .utf8)!
    }

    private func stroke(_ id: String, t: Double, club: String = "7i", lat: Double? = nil, acc: Double = 5, landingLat: Double? = nil) -> [String: Any] {
        var s: [String: Any] = ["id": id, "club": club, "mods": [String](), "t": t]
        if let lat { s["lat"] = lat; s["lng"] = 18.0; s["acc"] = acc }
        if let landingLat { s["landing"] = ["lat": landingLat, "lng": 18.0, "acc": 5.0] }
        return s
    }

    private func pos(_ lat: Double, acc: Double = 5) -> WatchEvent.Position {
        WatchEvent.Position(lat: lat, lng: 18, acc: acc)
    }

    private func state(_ json: String) -> RoundState {
        var state = RoundState()
        XCTAssertEqual(state.receive(snapshotJSON: json), .applied)
        return state
    }

    // MARK: What is shown

    func testStrokesMergeTheOutboxInPlayingOrder() {
        var s = state(snapshotJSON(strokes: [1: [stroke("p1", t: 1000), stroke("p2", t: 3000)]]))
        XCTAssertNotNil(s.logStroke(id: "w1", club: "PW", mods: [], hole: 1, t: 2000, position: nil))
        XCTAssertEqual(s.strokes(on: 1).map(\.id), ["p1", "w1", "p2"])
    }

    func testRemovalsHereAndOnThePhoneHideStrokes() {
        var s = state(snapshotJSON(strokes: [1: [stroke("p1", t: 1), stroke("p2", t: 2), stroke("gone", t: 3)]], removed: ["gone"]))
        XCTAssertNotNil(s.removeStroke(id: "p2", hole: 1, t: 10))
        XCTAssertEqual(s.strokes(on: 1).map(\.id), ["p1"])
    }

    func testAStrokeAddedAndUndoneHereIsHidden() {
        var s = state(snapshotJSON())
        _ = s.logStroke(id: "w1", club: "7i", mods: [], hole: 1, t: 1, position: nil)
        _ = s.removeStroke(id: "w1", hole: 1, t: 2)
        XCTAssertEqual(s.strokes(on: 1), [])
    }

    func testCurrentHoleFollowsThePhoneOrAHoleFinishedHere() {
        var s = state(snapshotJSON(currentHole: 3))
        XCTAssertEqual(s.currentHole, 3)
        _ = s.finishHole(3, t: 1)
        XCTAssertEqual(s.currentHole, 4)
        _ = s.finishHole(9, t: 2)
        XCTAssertEqual(s.currentHole, 9, "never past the last hole")
    }

    func testNoRoundMeansNothingToShow() {
        let s = state(snapshotJSON(roundId: nil))
        XCTAssertNil(s.round)
        XCTAssertNil(s.currentHole)
        XCTAssertEqual(s.strokes(on: 1), [])
    }

    // MARK: What the watch refuses

    func testLockedHoleTakesNoStrokesOrRemovals() {
        var s = state(snapshotJSON(locked: [1], strokes: [1: [stroke("p1", t: 1)]]))
        XCTAssertTrue(s.isLocked(1))
        XCTAssertNil(s.logStroke(id: "w1", club: "7i", mods: [], hole: 1, t: 2, position: nil))
        XCTAssertNil(s.removeStroke(id: "p1", hole: 1, t: 3))
        XCTAssertEqual(s.outbox, [])
    }

    func testAHoleFinishedHereIsLockedUntilConfirmed() {
        var s = state(snapshotJSON())
        _ = s.finishHole(1, t: 1)
        XCTAssertTrue(s.isLocked(1))
        XCTAssertNil(s.logStroke(id: "w1", club: "7i", mods: [], hole: 1, t: 2, position: nil))
    }

    func testAFinishedRoundIsReadOnly() {
        var s = state(snapshotJSON(locked: Array(1...9), finished: true))
        XCTAssertTrue(s.isRoundFinished)
        XCTAssertNil(s.logStroke(id: "w1", club: "7i", mods: [], hole: 4, t: 1, position: nil))
    }

    func testNothingIsLoggedWithoutARound() {
        var s = state(snapshotJSON(roundId: nil))
        XCTAssertNil(s.logStroke(id: "w1", club: "7i", mods: [], hole: 1, t: 1, position: nil))
        XCTAssertNil(s.finishHole(1, t: 1))
    }

    // MARK: Events

    func testLoggedStrokeCarriesModifiersInThePhonesOrderAndThePosition() {
        var s = state(snapshotJSON())
        let event = s.logStroke(id: "w1", club: "SW", mods: [.rough, .chip], hole: 2, t: 5,
                                position: WatchEvent.Position(lat: 59, lng: 18, acc: 4))
        XCTAssertEqual(event?.type, .add)
        XCTAssertEqual(event?.roundId, "r")
        XCTAssertEqual(event?.hole, 2)
        XCTAssertEqual(event?.stroke?.mods, ["chip", "rough"])
        XCTAssertEqual(event?.stroke?.lat, 59)
        XCTAssertEqual(s.outbox.count, 1)
    }

    func testEventsAreEncodedAsTheProtocolSays() throws {
        var s = state(snapshotJSON())
        let event = try XCTUnwrap(s.removeStroke(id: "p1", hole: 3, t: 42))
        let json = try XCTUnwrap(SyncClient.encode([event]))
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]]).first
        XCTAssertEqual(decoded?["v"] as? Int, 2)
        XCTAssertEqual(decoded?["type"] as? String, "remove")
        XCTAssertEqual(decoded?["roundId"] as? String, "r")
        XCTAssertEqual(decoded?["hole"] as? Int, 3)
        XCTAssertEqual(decoded?["id"] as? String, "p1")
        XCTAssertEqual(decoded?["t"] as? Double, 42)
    }

    func testAnOutboxSavedBeforeVersioningStillLoads() throws {
        let old = #"[{"type":"finish","roundId":"r","hole":2,"t":1}]"#
        let events = try JSONDecoder().decode([WatchEvent].self, from: Data(old.utf8))
        XCTAssertEqual(events.first?.type, .finish)
        XCTAssertNil(events.first?.v)
    }

    func testALateFixFillsInTheQueuedStroke() {
        var s = state(snapshotJSON())
        _ = s.logStroke(id: "w1", club: "7i", mods: [], hole: 1, t: 1, position: nil)
        let event = s.fillPosition(WatchEvent.Position(lat: 59.5, lng: 18, acc: 6), strokeId: "w1", roundId: "r", hole: 1)
        XCTAssertEqual(event?.type, .position)
        XCTAssertEqual(s.outbox.first?.stroke?.lat, 59.5, "a resend of the add carries the position too")
    }

    func testALateFixForAStrokeNoLongerThereIsDropped() {
        var s = state(snapshotJSON())
        _ = s.logStroke(id: "w1", club: "7i", mods: [], hole: 1, t: 1, position: nil)
        _ = s.removeStroke(id: "w1", hole: 1, t: 2)
        XCTAssertNil(s.fillPosition(WatchEvent.Position(lat: 1, lng: 1, acc: 1), strokeId: "w1", roundId: "r", hole: 1))
        XCTAssertNil(s.fillPosition(WatchEvent.Position(lat: 1, lng: 1, acc: 1), strokeId: "x", roundId: "other", hole: 1))
    }

    // MARK: Snapshots and confirmation

    func testASnapshotConfirmsWhatThePhoneApplied() {
        var s = state(snapshotJSON())
        _ = s.logStroke(id: "added", club: "7i", mods: [], hole: 1, t: 1, position: nil)
        _ = s.logStroke(id: "refused", club: "7i", mods: [], hole: 1, t: 2, position: nil)
        _ = s.logStroke(id: "pending", club: "7i", mods: [], hole: 1, t: 3, position: nil)
        _ = s.removeStroke(id: "p9", hole: 2, t: 4)
        _ = s.finishHole(3, t: 5)
        XCTAssertEqual(s.outbox.count, 5)
        _ = s.receive(snapshotJSON: snapshotJSON(locked: [3], strokes: [1: [stroke("added", t: 1)]], removed: ["refused", "p9"]))
        XCTAssertEqual(s.outbox.compactMap { $0.stroke?.id }, ["pending"], "only the stroke the phone hasn't seen stays")
    }

    func testARemovalRefusedByALockCountsAsConfirmed() {
        var s = state(snapshotJSON(strokes: [2: [stroke("p1", t: 1)]]))
        _ = s.removeStroke(id: "p1", hole: 2, t: 2)
        _ = s.receive(snapshotJSON: snapshotJSON(locked: [2], strokes: [2: [stroke("p1", t: 1)]]))
        XCTAssertEqual(s.outbox, [], "the phone refused it; resending would not change that")
    }

    func testAPositionIsConfirmedOnceTheStrokeHasOne() {
        var s = state(snapshotJSON())
        _ = s.logStroke(id: "w1", club: "7i", mods: [], hole: 1, t: 1, position: nil)
        _ = s.fillPosition(WatchEvent.Position(lat: 59, lng: 18, acc: 5), strokeId: "w1", roundId: "r", hole: 1)
        _ = s.receive(snapshotJSON: snapshotJSON(strokes: [1: [stroke("w1", t: 1)]]))
        XCTAssertEqual(s.outbox.map(\.type), [.position], "the add is confirmed, the position not yet")
        _ = s.receive(snapshotJSON: snapshotJSON(strokes: [1: [stroke("w1", t: 1, lat: 59)]]))
        XCTAssertEqual(s.outbox, [])
    }

    func testEventsForAnotherRoundAreDroppedWhenTheRoundChanges() {
        var s = state(snapshotJSON())
        _ = s.logStroke(id: "w1", club: "7i", mods: [], hole: 1, t: 1, position: nil)
        _ = s.receive(snapshotJSON: snapshotJSON(roundId: "next"))
        XCTAssertEqual(s.outbox, [])
        XCTAssertEqual(s.round?.id, "next")
    }

    func testNoRoundOnThePhoneClearsTheOutbox() {
        var s = state(snapshotJSON())
        _ = s.logStroke(id: "w1", club: "7i", mods: [], hole: 1, t: 1, position: nil)
        _ = s.receive(snapshotJSON: snapshotJSON(roundId: nil))
        XCTAssertEqual(s.outbox, [])
    }

    func testASnapshotFromANewerPhoneAppIsIgnored() {
        var s = state(snapshotJSON(currentHole: 2))
        XCTAssertEqual(s.receive(snapshotJSON: snapshotJSON(currentHole: 7, v: 3)), .newerVersion)
        XCTAssertEqual(s.currentHole, 2, "the round already here keeps working")
    }

    func testASnapshotWithoutVersionCountsAsVersionOne() {
        var s = RoundState()
        XCTAssertEqual(s.receive(snapshotJSON: snapshotJSON(v: nil)), .applied)
    }

    func testAnUnreadableSnapshotChangesNothing() {
        var s = state(snapshotJSON(currentHole: 4))
        XCTAssertEqual(s.receive(snapshotJSON: "{not json"), .unreadable)
        XCTAssertEqual(s.currentHole, 4)
    }

    func testAFinishedRoundFromAnOlderPhoneWithoutTheFieldIsNotFinished() {
        let s = state(snapshotJSON(finished: nil))
        XCTAssertFalse(s.isRoundFinished)
    }

    func testAVersionOneSnapshotStillApplies() {
        var s = RoundState()
        XCTAssertEqual(s.receive(snapshotJSON: snapshotJSON(v: 1)), .applied)
    }

    func testALateFixDoesNotHideItsStroke() {
        var s = state(snapshotJSON())
        _ = s.logStroke(id: "w1", club: "7i", mods: [], hole: 1, t: 1, position: nil)
        _ = s.fillPosition(pos(59), strokeId: "w1", roundId: "r", hole: 1)
        XCTAssertEqual(s.strokes(on: 1).map(\.id), ["w1"])
    }

    // MARK: Extra strokes

    func testExtraStrokesComeFromThePhone() {
        let s = state(snapshotJSON(extra: [1: 2, 2: 1, 3: 0]))
        XCTAssertEqual(s.extra(1), 2)
        XCTAssertEqual(s.extra(3), 0)
        XCTAssertNil(s.extra(4), "no handicap on the hole: nothing")
    }

    // MARK: Marking the hole

    func testMarkingShowsAtOnceAndTheNewestMarkWins() {
        var s = state(snapshotJSON(marked: [2: ["lat": 59.0, "lng": 18.0, "acc": 8, "t": 100]]))
        XCTAssertEqual(s.holePosition(2)?.acc, 8, "marked on the phone")
        XCTAssertNotNil(s.markHole(2, position: pos(59.001, acc: 4), t: 200))
        XCTAssertEqual(s.holePosition(2)?.acc, 4, "the mark made here is newer")
        XCTAssertNotNil(s.markHole(2, position: pos(59.002, acc: 3), t: 300))
        XCTAssertEqual(s.holePosition(2)?.lat, 59.002, "marking again replaces it")
    }

    func testALockedHoleCannotBeMarked() {
        var s = state(snapshotJSON(locked: [2]))
        XCTAssertNil(s.markHole(2, position: pos(59), t: 1))
    }

    func testAMarkIsConfirmedWhenThePhoneHasItOrANewerOne() {
        var s = state(snapshotJSON())
        _ = s.markHole(2, position: pos(59), t: 200)
        _ = s.receive(snapshotJSON: snapshotJSON(marked: [2: ["lat": 58.0, "lng": 18.0, "acc": 5, "t": 100]]))
        XCTAssertEqual(s.outbox.count, 1, "the phone's older mark does not confirm it")
        _ = s.receive(snapshotJSON: snapshotJSON(marked: [2: ["lat": 59.0, "lng": 18.0, "acc": 5, "t": 200]]))
        XCTAssertEqual(s.outbox, [])
        _ = s.markHole(3, position: pos(59), t: 300)
        _ = s.receive(snapshotJSON: snapshotJSON(locked: [3]))
        XCTAssertEqual(s.outbox, [], "refused because the hole is locked")
    }

    // MARK: Locking a shot's distance

    func testLockingSetsTheLandingAtOnce() {
        var s = state(snapshotJSON(strokes: [1: [stroke("p1", t: 1, lat: 59)]]))
        XCTAssertNotNil(s.lockLanding(strokeId: "p1", hole: 1, position: pos(59.001), t: 2))
        XCTAssertEqual(s.strokes(on: 1).first?.landing?.lat, 59.001)
    }

    func testLockingFollowsThePhonesRules() {
        var s = state(snapshotJSON(locked: [3], strokes: [
            1: [stroke("putt", t: 1, club: "Putter", lat: 59), stroke("pen", t: 2, club: "Penalty", lat: 59)],
            2: [stroke("nopos", t: 1), stroke("done", t: 2, lat: 59, landingLat: 59.001)],
            3: [stroke("locked", t: 1, lat: 59)]
        ]))
        XCTAssertNil(s.lockLanding(strokeId: "putt", hole: 1, position: pos(59.001), t: 3), "no distance for a putt")
        XCTAssertNil(s.lockLanding(strokeId: "pen", hole: 1, position: pos(59.001), t: 3), "or a penalty stroke")
        XCTAssertNil(s.lockLanding(strokeId: "nopos", hole: 2, position: pos(59.001), t: 3), "nothing to measure from")
        XCTAssertNil(s.lockLanding(strokeId: "done", hole: 2, position: pos(59.002), t: 3), "already locked")
        XCTAssertNil(s.lockLanding(strokeId: "locked", hole: 3, position: pos(59.001), t: 3), "hole locked")
        XCTAssertEqual(s.outbox, [])
    }

    func testALandingIsConfirmedWhenThePhoneHasItOrRefusedIt() {
        var s = state(snapshotJSON(strokes: [1: [stroke("p1", t: 1, lat: 59)], 2: [stroke("p2", t: 1, lat: 59)]]))
        _ = s.lockLanding(strokeId: "p1", hole: 1, position: pos(59.001), t: 2)
        _ = s.lockLanding(strokeId: "p2", hole: 2, position: pos(59.001), t: 2)
        _ = s.receive(snapshotJSON: snapshotJSON(strokes: [1: [stroke("p1", t: 1, lat: 59)], 2: [stroke("p2", t: 1, lat: 59)]]))
        XCTAssertEqual(s.outbox.count, 2, "not applied yet")
        _ = s.receive(snapshotJSON: snapshotJSON(locked: [2], strokes: [1: [stroke("p1", t: 1, lat: 59, landingLat: 59.001)], 2: [stroke("p2", t: 1, lat: 59)]]))
        XCTAssertEqual(s.outbox, [])
    }

    // MARK: The distance line

    func testNothingToMeasure() {
        let s = state(snapshotJSON(strokes: [2: [stroke("putt", t: 1, club: "Putter", lat: 59)], 3: [stroke("nopos", t: 1)]]))
        XCTAssertEqual(s.shotDistance(on: 1, fix: pos(59.001)), .none, "no stroke yet")
        XCTAssertEqual(s.shotDistance(on: 2, fix: pos(59.001)), .none, "a putt")
        XCTAssertEqual(s.shotDistance(on: 3, fix: pos(59.001)), .none, "no position")
        XCTAssertEqual(state(snapshotJSON(strokes: [1: [stroke("p1", t: 1, lat: 59)]])).shotDistance(on: 1, fix: nil), .none, "no fix")
    }

    func testLiveDistanceFromTheLastStroke() {
        let s = state(snapshotJSON(strokes: [1: [stroke("tee", t: 1, lat: 58.9), stroke("p1", t: 2, lat: 59)]]))
        XCTAssertEqual(s.shotDistance(on: 1, fix: pos(59.001)), .live("111", strokeId: "p1"))
        XCTAssertEqual(s.shotDistance(on: 1, fix: pos(59.001, acc: 30)), .live("≈ 111", strokeId: "p1"), "poor accuracy")
    }

    func testALockedDistanceStaysPut() {
        let s = state(snapshotJSON(strokes: [1: [stroke("p1", t: 1, lat: 59, landingLat: 59.001)]]))
        XCTAssertEqual(s.shotDistance(on: 1, fix: pos(59.005)), .locked("111"))
        XCTAssertEqual(s.shotDistance(on: 1, fix: nil), .locked("111"), "shown without GPS too")
    }

    func testDistanceAndFormatMatchThePhone() {
        XCTAssertEqual(meters(pos(59), pos(59.001)), 111.19, accuracy: 0.05)
        XCTAssertEqual(formatDistance(0.4, approx: false), "<1")
        XCTAssertEqual(formatDistance(125.6, approx: true), "≈ 126")
    }

    // MARK: Suggested club (#6)

    func testTheFirstStrokeUsesThePhonesTeeClub() {
        let s = state(snapshotJSON(bag: ["Driver", "3W", "7i", "Putter"], tee: [1: "3W"]))
        XCTAssertEqual(s.club(on: 1, picked: nil), "3W")
    }

    func testWithoutHistoryDriverOrSevenIronOnAParThree() {
        let s = state(snapshotJSON(bag: ["Driver", "7i", "Putter"], pars: [2: 3]))
        XCTAssertEqual(s.club(on: 1, picked: nil), "Driver")
        XCTAssertEqual(s.club(on: 2, picked: nil), "7i")
    }

    func testNeverPutterOrAClubOutsideTheBagOffTheTee() {
        // The tee club is no longer in the bag, nor are Driver and 7i: the first club that isn't the putter.
        let s = state(snapshotJSON(bag: ["Putter", "Hybrid", "PW"], tee: [1: "3W"]))
        XCTAssertEqual(s.club(on: 1, picked: nil), "Hybrid")
    }

    func testThePuttOnTheLastHoleDoesNotCarryOver() {
        let s = state(snapshotJSON(currentHole: 2, strokes: [1: [stroke("a", t: 1, club: "Driver"), stroke("b", t: 2, club: "Putter")]]))
        let picked = RoundState.PickedClub(club: "Putter", roundId: "r", hole: 1, t: 2)
        XCTAssertEqual(s.club(on: 2, picked: picked), "Driver")
    }

    func testOnAHoleWithStrokesTheLastClubPlayedSkippingPenalty() {
        let s = state(snapshotJSON(strokes: [1: [stroke("a", t: 1, club: "Driver"), stroke("b", t: 2, club: "Putter"), stroke("c", t: 3, club: "Penalty")]]))
        XCTAssertEqual(s.club(on: 1, picked: nil), "Putter")
    }

    func testAClubPickedOnTheWatchWinsUntilAStrokeAfterIt() {
        var s = state(snapshotJSON(strokes: [1: [stroke("a", t: 1, club: "Driver")]]))
        let picked = RoundState.PickedClub(club: "7i", roundId: "r", hole: 1, t: 5)
        XCTAssertEqual(s.club(on: 1, picked: picked), "7i")
        // A putt logged later (here on the watch; the same goes for one from the phone) takes over.
        _ = s.logStroke(id: "w1", club: "Putter", mods: [], hole: 1, t: 6, position: nil)
        XCTAssertEqual(s.club(on: 1, picked: picked), "Putter")
        // A pick for another round doesn't count.
        let other = RoundState.PickedClub(club: "7i", roundId: "old", hole: 2, t: 9)
        XCTAssertEqual(s.club(on: 2, picked: other), "Driver")
    }
}
