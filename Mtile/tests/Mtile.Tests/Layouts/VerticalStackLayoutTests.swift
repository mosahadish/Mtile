// Port of tests/Wtile.Tests/Layouts/VerticalStackLayoutTests.cs
import XCTest
@testable import Mtile

final class VerticalStackLayoutTests: XCTestCase {
    private let workArea = LayoutRect(x: 0, y: 24, width: 1920, height: 1056)

    private func params(gap: Int = 0) -> [String: Double] {
        ["gap": Double(gap)]
    }

    private static func overlaps(_ a: LayoutRect, _ b: LayoutRect) -> Bool {
        a.x < b.x + b.width && a.x + a.width > b.x && a.y < b.y + b.height && a.y + a.height > b.y
    }

    func testNameAndSymbol() {
        let layout = VerticalStackLayout()
        XCTAssertEqual(layout.name, "vertical")
        XCTAssertEqual(layout.symbol, "=")
    }

    func testNoWindows_ReturnsEmpty() {
        let layout = VerticalStackLayout()
        XCTAssertTrue(layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: 0, params: params())).isEmpty)
    }

    func testSingleWindow_FillsEntireWorkArea() {
        let layout = VerticalStackLayout()
        let result = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: 1, params: params()))

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0], workArea)
    }

    func testThreeWindows_FullWidthRowsStackedTopToBottom() {
        let layout = VerticalStackLayout()
        let result = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: 3, params: params()))

        XCTAssertEqual(result.count, 3)
        for r in result {
            XCTAssertEqual(r.x, workArea.x)
            XCTAssertEqual(r.width, workArea.width)
        }

        XCTAssertEqual(result[0].y, workArea.y)
        XCTAssertEqual(result[1].y, result[0].y + result[0].height)
        XCTAssertEqual(result[2].y, result[1].y + result[1].height)
        XCTAssertEqual(result[0].height + result[1].height + result[2].height, workArea.height)
    }

    func testGap_InsetsEveryRectOnAllSides() {
        let layout = VerticalStackLayout()
        let gap = 10
        let noGap = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: 3, params: params(gap: 0)))
        let withGap = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: 3, params: params(gap: gap)))

        XCTAssertEqual(withGap.count, noGap.count)
        for i in 0..<noGap.count {
            XCTAssertEqual(withGap[i].x, noGap[i].x + gap / 2)
            XCTAssertEqual(withGap[i].y, noGap[i].y + gap / 2)
            XCTAssertEqual(withGap[i].width, noGap[i].width - gap)
            XCTAssertEqual(withGap[i].height, noGap[i].height - gap)
        }
    }

    func testRectanglesNeverOverlap_ForVariousWindowCounts() {
        let layout = VerticalStackLayout()
        for n in 1...8 {
            let result = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: n, params: params()))
            for i in 0..<result.count {
                for j in (i + 1)..<result.count {
                    XCTAssertFalse(Self.overlaps(result[i], result[j]), "n=\(n): rect \(i) overlaps rect \(j)")
                }
            }
        }
    }
}