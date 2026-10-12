import XCTest
@testable import StrokeCounterWatch

// The swing detector on made-up motion at 100 Hz: a swing is a fast turn with a jolt near it.
final class SwingDetectorTests: XCTestCase {
    // Feeds `seconds` of samples from `from`, with rotation and acceleration given per time; returns the swings.
    private func run(_ detector: inout SwingDetector, from: Double = 0, seconds: Double,
                     rotation: (Double) -> Double, acceleration: (Double) -> Double) -> [SwingDetector.Swing] {
        var swings: [SwingDetector.Swing] = []
        for i in 0..<Int(seconds * 100) {
            let t = from + Double(i) / 100
            if let swing = detector.add(t: t, rotation: rotation(t), acceleration: acceleration(t)) { swings.append(swing) }
        }
        return swings
    }

    private func pulse(at center: Double, peak: Double, width: Double, base: Double) -> (Double) -> Double {
        { t in abs(t - center) <= width / 2 ? peak * (1 - abs(t - center) / (width / 2)) + base : base }
    }

    func testAFullSwingWithImpactIsFound() {
        var d = SwingDetector()
        let swings = run(&d, seconds: 5, rotation: pulse(at: 2, peak: 25, width: 0.4, base: 0.5),
                         acceleration: pulse(at: 2.05, peak: 8, width: 0.06, base: 0.1))
        XCTAssertEqual(swings.count, 1)
        XCTAssertEqual(swings[0].t, 2, accuracy: 0.02)
        XCTAssertGreaterThanOrEqual(swings[0].impact, 4)
    }

    func testATurnWithoutAJoltIsNotASwing() {
        var d = SwingDetector()
        XCTAssertTrue(run(&d, seconds: 5, rotation: pulse(at: 2, peak: 25, width: 0.4, base: 0.5), acceleration: { _ in 1.5 }).isEmpty)
    }

    func testWalkingAndHandlingAreIgnored() {
        var d = SwingDetector()
        XCTAssertTrue(run(&d, seconds: 30, rotation: { t in 4 + 3 * sin(t * 6) }, acceleration: { t in 0.6 + 0.5 * abs(sin(t * 3)) }).isEmpty)
    }

    func testTwoSwingsSecondsApartAreTwo() {
        var d = SwingDetector()
        let rotation: (Double) -> Double = { t in max(self.pulse(at: 2, peak: 22, width: 0.4, base: 0.3)(t), self.pulse(at: 9, peak: 24, width: 0.4, base: 0.3)(t)) }
        let acceleration: (Double) -> Double = { t in max(self.pulse(at: 2.05, peak: 6, width: 0.06, base: 0.1)(t), self.pulse(at: 9.05, peak: 7, width: 0.06, base: 0.1)(t)) }
        XCTAssertEqual(run(&d, seconds: 12, rotation: rotation, acceleration: acceleration).count, 2)
    }

    func testAJoltJustBeforeTheTurnCounts() {
        var d = SwingDetector()
        let swings = run(&d, seconds: 5, rotation: pulse(at: 2, peak: 20, width: 0.4, base: 0.3),
                         acceleration: pulse(at: 1.75, peak: 6, width: 0.04, base: 0.1))
        XCTAssertEqual(swings.count, 1)
    }
}
