// Port of tests/Wtile.Tests/Core/DropTargetTests.cs
import XCTest
@testable import Mtile

final class DropTargetTests: XCTestCase {
    private let tile = LayoutRect(x: 100, y: 100, width: 400, height: 200)

    func testDropsAfterTile_FollowsTheTriangleTheCursorIsIn() {
        let cases: [(x: Int, y: Int, expected: Bool)] = [
            (110, 200, false), // left triangle
            (490, 200, true),  // right triangle
            (300, 110, false), // top triangle
            (300, 290, true),  // bottom triangle
        ]
        for c in cases {
            XCTAssertEqual(DropTarget.dropsAfterTile(tile, x: c.x, y: c.y), c.expected, "(\(c.x), \(c.y))")
        }
    }

    func testDropsAfterTile_ScalesTheDiagonalsToAWideTile() {
        // Further right than down from center, yet still in the bottom triangle of a wide tile.
        XCTAssertTrue(DropTarget.dropsAfterTile(tile, x: 430, y: 280))
        XCTAssertTrue(DropTarget.dropsAfterTile(tile, x: 150, y: 290))
    }

    func testDistanceSquaredToRect_IsZeroInside() {
        XCTAssertEqual(DropTarget.distanceSquaredToRect(tile, x: 300, y: 200), 0)
    }

    func testDistanceSquaredToRect_MeasuresToTheNearestEdge() {
        XCTAssertEqual(DropTarget.distanceSquaredToRect(tile, x: 90, y: 200), 100)
        XCTAssertEqual(DropTarget.distanceSquaredToRect(tile, x: 504, y: 309), 25 + 100)
    }
}