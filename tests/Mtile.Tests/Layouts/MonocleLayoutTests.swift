// Port of tests/Wtile.Tests/Layouts/MonocleLayoutTests.cs
import XCTest
@testable import Mtile

final class MonocleLayoutTests: XCTestCase {
    private let workArea = LayoutRect(x: 0, y: 24, width: 1920, height: 1056)

    func testNameAndSymbol() {
        let layout = MonocleLayout()
        XCTAssertEqual(layout.name, "monocle")
        XCTAssertEqual(layout.symbol, "[M]")
    }

    func testNoWindows_ReturnsEmpty() {
        let layout = MonocleLayout()
        let result = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: 0, params: [:]))
        XCTAssertTrue(result.isEmpty)
    }

    func testEveryWindow_GetsTheFullWorkArea() {
        let layout = MonocleLayout()
        let result = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: 4, params: [:]))

        XCTAssertEqual(result.count, 4)
        for r in result {
            XCTAssertEqual(r, workArea)
        }
    }
}