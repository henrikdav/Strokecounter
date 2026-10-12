#if DEBUG
import CoreLocation
import Foundation

// Made-up rounds for the Xcode previews of the watch screens (the #Preview blocks at the end of each view file).
// Nothing here runs in the app.
enum PreviewData {
    static let bag = ["Driver", "3W", "Hybrid", "5i", "6i", "7i", "8i", "9i", "PW", "GW", "SW", "Putter"]

    // A nine-hole round on hole 3 (par 4, one handicap stroke): a drive and a 7i played, holes 1–2 done and locked.
    static func round(currentHole: Int = 3, locked: [Int] = [1, 2], finished: Bool = false,
                      strokesOnHole3: Int = 2, marked: Bool = false) -> Snapshot {
        let pars = [4, 5, 4, 3, 4, 4, 5, 3, 4]
        let holes: [[String: Any]] = pars.enumerated().map { i, par in
            var hole: [String: Any] = ["number": i + 1, "par": par, "index": [7, 1, 13, 17, 3, 11, 5, 15, 9][i],
                                       "extra": i == 2 || i == 1 || i == 4 ? 1 : 0]
            if marked && i == 2 { hole["position"] = ["lat": 59.20250, "lng": 18.00000, "acc": 5, "t": 0] }
            return hole
        }
        let played: [[String: Any]] = [
            ["id": "p1", "club": "Driver", "mods": [String](), "t": 1, "lat": 59.20000, "lng": 18.00000, "acc": 5],
            ["id": "p2", "club": "7i", "mods": ["rough"], "t": 2, "lat": 59.20190, "lng": 18.00010, "acc": 6]
        ]
        let round: [String: Any] = [
            "id": "preview", "name": "Ågesta GK", "holes": holes, "currentHole": currentHole, "locked": locked,
            "finished": finished, "removed": [String](),
            "strokes": [
                "1": [["id": "a1", "club": "Driver", "mods": [String](), "t": 0], ["id": "a2", "club": "PW", "mods": [String](), "t": 0],
                      ["id": "a3", "club": "Putter", "mods": [String](), "t": 0], ["id": "a4", "club": "Putter", "mods": [String](), "t": 0]],
                "2": [["id": "b1", "club": "Driver", "mods": [String](), "t": 0], ["id": "b2", "club": "5i", "mods": [String](), "t": 0],
                      ["id": "b3", "club": "SW", "mods": ["bunker"], "t": 0], ["id": "b4", "club": "Putter", "mods": [String](), "t": 0]],
                "3": Array(played.prefix(strokesOnHole3))
            ]
        ]
        let json: [String: Any] = ["v": 2, "round": round, "bag": bag, "club": "Driver"]
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(Snapshot.self, from: data)
    }

    // Where the player stands now: about 45 m on from the 7i.
    static let fix = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 59.20230, longitude: 18.00010),
                                altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: Date())

    static func store(_ snapshot: Snapshot? = round(), fix: CLLocation? = PreviewData.fix) -> WatchStore {
        WatchStore(preview: snapshot, fix: fix)
    }

    static var loggedStroke: Snapshot.Stroke { round().round!.strokes["3"]![1] }
}
#endif
