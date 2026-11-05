// Port of tests/Wtile.Tests/Layouts/DwindleLayoutTests.cs
import XCTest
@testable import Mtile

final class DwindleLayoutTests: XCTestCase {
    private let workArea = LayoutRect(x: 0, y: 24, width: 1920, height: 1056) // below a 24px bar

    private func params(nmaster: Int = 1, mfact: Double = 0.55, gap: Int = 0) -> [String: Double] {
        ["nmaster": Double(nmaster), "mfact": mfact, "gap": Double(gap)]
    }

    private static func rounded(_ length: Int, _ fraction: Double) -> Int {
        Int((Double(length) * fraction).rounded(.toNearestOrEven))
    }

    private static func overlaps(_ a: LayoutRect, _ b: LayoutRect) -> Bool {
        a.x < b.x + b.width && a.x + a.width > b.x && a.y < b.y + b.height && a.y + a.height > b.y
    }

    func testNameAndSymbol() {
        let layout = DwindleLayout()
        XCTAssertEqual(layout.name, "dwindle")
        XCTAssertEqual(layout.symbol, "[\\]")
    }

    func testNoWindows_ReturnsEmpty() {
        let layout = DwindleLayout()
        let result = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: 0, params: params()))
        XCTAssertTrue(result.isEmpty)
    }

    func testSingleWindow_FillsEntireWorkArea() {
        let layout = DwindleLayout()
        let result = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: 1, params: params()))

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0], workArea)
    }

    func testTwoWindows_SplitsAtMfact_SecondWindowGetsFullRemainder() {
        let layout = DwindleLayout()
        let result = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: 2, params: params(mfact: 0.55)))

        let expectedFirstWidth = Self.rounded(workArea.width, 0.55)
        XCTAssertEqual(result[0].x, workArea.x)
        XCTAssertEqual(result[0].y, workArea.y)
        XCTAssertEqual(result[0].width, expectedFirstWidth)
        XCTAssertEqual(result[0].height, workArea.height)

        XCTAssertEqual(result[1].x, workArea.x + expectedFirstWidth)
        XCTAssertEqual(result[1].y, workArea.y)
        XCTAssertEqual(result[1].width, workArea.width - expectedFirstWidth)
        XCTAssertEqual(result[1].height, workArea.height)
    }

    func testThreeWindows_SpiralsLeftColumn_TopRight_BottomRight() {
        let layout = DwindleLayout()
        let result = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: 3, params: params(mfact: 0.5)))

        let leftWidth = Self.rounded(workArea.width, 0.5)
        let rightWidth = workArea.width - leftWidth
        let rightX = workArea.x + leftWidth
        let topHeight = Self.rounded(workArea.height, 0.5)
        let bottomHeight = workArea.height - topHeight

        XCTAssertEqual(result[0], LayoutRect(x: workArea.x, y: workArea.y, width: leftWidth, height: workArea.height))
        XCTAssertEqual(result[1], LayoutRect(x: rightX, y: workArea.y, width: rightWidth, height: topHeight))
        XCTAssertEqual(result[2], LayoutRect(x: rightX, y: workArea.y + topHeight, width: rightWidth, height: bottomHeight))
    }

    func testFourWindows_AlternatesAxisEachStep() {
        let layout = DwindleLayout()
        let result = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: 4, params: params(mfact: 0.5)))

        // The 3rd split (i=2, vertical again) happens within the bottom-right remainder:
        // result[2] is its left half, result[3] its right half (same y/height, split x).
        XCTAssertEqual(result[3].y, result[2].y)
        XCTAssertEqual(result[3].height, result[2].height)
        XCTAssertEqual(result[3].x, result[2].x + result[2].width)
    }

    func testNmasterParamIsIgnored() {
        let layout = DwindleLayout()
        let withNmaster1 = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: 4, params: params(nmaster: 1)))
        let withNmaster5 = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: 4, params: params(nmaster: 5)))

        XCTAssertEqual(withNmaster5, withNmaster1)
    }

    func testGap_InsetsEveryRect() {
        let layout = DwindleLayout()
        let gap = 10
        let noGap = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: 4, params: params(gap: 0)))
        let withGap = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: 4, params: params(gap: gap)))

        XCTAssertEqual(withGap.count, noGap.count)
        for i in 0..<noGap.count {
            XCTAssertEqual(withGap[i].x, noGap[i].x + gap / 2)
            XCTAssertEqual(withGap[i].y, noGap[i].y + gap / 2)
            XCTAssertEqual(withGap[i].width, noGap[i].width - gap)
            XCTAssertEqual(withGap[i].height, noGap[i].height - gap)
        }
    }

    func testNoOverlapAndFullCoverage_ForVariousWindowCounts() {
        let layout = DwindleLayout()
        for n in 1...8 {
            let result = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: n, params: params(gap: 0)))

            for i in 0..<result.count {
                for j in (i + 1)..<result.count {
                    XCTAssertFalse(Self.overlaps(result[i], result[j]), "n=\(n): rect \(i) overlaps rect \(j)")
                }
            }

            var totalArea = 0
            for r in result {
                totalArea += r.width * r.height
            }
            XCTAssertEqual(totalArea, workArea.width * workArea.height)
        }
    }
}