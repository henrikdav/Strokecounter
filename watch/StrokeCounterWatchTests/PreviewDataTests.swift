import XCTest
@testable import StrokeCounterWatch

// The made-up rounds behind the Xcode previews decode and show what the previews expect.
final class PreviewDataTests: XCTestCase {
    func testThePreviewRoundsDecode() {
        let store = PreviewData.store()
        XCTAssertEqual(store.currentHole, 3)
        XCTAssertEqual(store.strokes(on: 3).map(\.club), ["Driver", "7i"])
        XCTAssertEqual(store.bag.count, 12)
        XCTAssertNotNil(store.freshFix)
        XCTAssertTrue(PreviewData.store(PreviewData.round(locked: [1, 2, 3])).isLocked(3))
        XCTAssertTrue(PreviewData.store(PreviewData.round(locked: Array(1...9), finished: true)).isRoundFinished)
        XCTAssertNotNil(PreviewData.store(PreviewData.round(marked: true)).holePosition(3))
        XCTAssertNil(PreviewData.store(nil).currentHole)
    }
}
