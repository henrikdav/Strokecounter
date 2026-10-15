import XCTest
@testable import StrokeCounterWatch

// The green page's distance to the hole: as exact as the GPS allows, and the hole's mark averaged from a few fixes.
final class GreenDistanceTests: XCTestCase {
    private let cup = WatchEvent.Position(lat: 59.2025, lng: 18.0, acc: 4)

    // A position `north` meters north of the cup, with the given accuracy.
    private func at(_ north: Double, acc: Double) -> WatchEvent.Position {
        WatchEvent.Position(lat: cup.lat + north / 111_195, lng: cup.lng, acc: acc)
    }

    func testNothingWithoutMarkOrFix() {
        XCTAssertEqual(GreenDistance.reading(mark: nil, now: at(10, acc: 4)), .none)
        XCTAssertEqual(GreenDistance.reading(mark: cup, now: nil), .none)
    }

    func testGoodGPSShowsTheMeters() {
        XCTAssertEqual(GreenDistance.reading(mark: cup, now: at(14, acc: 4)), .meters(14, rough: false))
    }

    func testPoorGPSShowsTheMetersAsRough() {
        XCTAssertEqual(GreenDistance.reading(mark: cup, now: at(14, acc: 9)), .meters(14, rough: true))
    }

    func testCloseWithGoodGPSIsUnderThree() {
        XCTAssertEqual(GreenDistance.reading(mark: cup, now: at(2, acc: 4)), .near(3))
        XCTAssertEqual(GreenDistance.reading(mark: cup, now: at(4, acc: 4)), .meters(4, rough: false))
    }

    // With poor GPS, "near" grows with the uncertainty: 4 m and 12 m give √160 ≈ 12.6, half of it 6.3 → "< 7".
    func testCloseWithPoorGPSGrowsWithTheUncertainty() {
        XCTAssertEqual(GreenDistance.reading(mark: cup, now: at(5, acc: 12)), .near(7))
        XCTAssertEqual(GreenDistance.reading(mark: cup, now: at(8, acc: 12)), .meters(8, rough: true))
    }

    func testAveragedIsNilWithoutFixes() {
        XCTAssertNil(GreenDistance.averaged([]))
    }

    func testAveragedWeighsByAccuracyAndKeepsTheBest() {
        // Two equal fixes 2 m apart: the middle.
        let middle = GreenDistance.averaged([at(0, acc: 4), at(2, acc: 4)])!
        XCTAssertEqual(meters(middle, at(1, acc: 4)), 0, accuracy: 0.01)
        XCTAssertEqual(middle.acc, 4)
        // A fix at 6 m counts a quarter as much as one at 3 m: (0·4 + 3·1) / 5 = 0.6 m.
        let weighted = GreenDistance.averaged([at(0, acc: 3), at(3, acc: 6)])!
        XCTAssertEqual(meters(weighted, at(0.6, acc: 3)), 0, accuracy: 0.01)
        XCTAssertEqual(weighted.acc, 3)
    }

    func testAveragedLeavesOutAFixFarWorseThanTheBest() {
        let mark = GreenDistance.averaged([at(0, acc: 4), at(0, acc: 4), at(20, acc: 15)])!
        XCTAssertEqual(meters(mark, cup), 0, accuracy: 0.01)
    }
}
