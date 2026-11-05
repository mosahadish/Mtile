// Port of tests/Wtile.Tests/Layouts/LayoutRectTests.cs
import XCTest
@testable import Mtile

final class LayoutRectTests: XCTestCase {
    func testNormalRect_IsNotEmpty() {
        XCTAssertFalse(LayoutRect(x: 0, y: 0, width: 1920, height: 1080).isEmpty)
    }

    func testOffOriginRect_IsNotEmpty() {
        XCTAssertFalse(LayoutRect(x: -1920, y: 200, width: 1280, height: 1024).isEmpty)
    }

    func testDegenerateRect_IsEmpty() {
        let cases: [(x: Int, y: Int, width: Int, height: Int)] = [
            (0, 0, 0, 0),     // a screen that just disappeared
            (0, 0, 1920, 0),
            (0, 0, 0, 1080),
            (0, 0, -10, -10), // bar insets can over-subtract a tiny work area
        ]
        for c in cases {
            XCTAssertTrue(LayoutRect(x: c.x, y: c.y, width: c.width, height: c.height).isEmpty, "\(c)")
        }
    }
}