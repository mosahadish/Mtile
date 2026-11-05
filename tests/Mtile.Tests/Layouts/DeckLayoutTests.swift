// Port of tests/Wtile.Tests/Layouts/DeckLayoutTests.cs
import XCTest
@testable import Mtile

final class DeckLayoutTests: XCTestCase {
    private let workArea = LayoutRect(x: 0, y: 24, width: 1920, height: 1056) // below a 24px bar

    private func params(nmaster: Int = 1, mfact: Double = 0.55, gap: Int = 0) -> [String: Double] {
        ["nmaster": Double(nmaster), "mfact": mfact, "gap": Double(gap)]
    }

    private static func roundedWidth(_ width: Int, _ fraction: Double) -> Int {
        Int((Double(width) * fraction).rounded(.toNearestOrEven))
    }

    private static func overlaps(_ a: LayoutRect, _ b: LayoutRect) -> Bool {
        a.x < b.x + b.width && a.x + a.width > b.x && a.y < b.y + b.height && a.y + a.height > b.y
    }

    func testNameAndSymbol() {
        let layout = DeckLayout()
        XCTAssertEqual(layout.name, "deck")
        XCTAssertEqual(layout.symbol, "[D]")
    }

    func testNoWindows_ReturnsEmpty() {
        let layout = DeckLayout()
        let result = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: 0, params: params()))
        XCTAssertTrue(result.isEmpty)
    }

    func testSingleWindow_FillsEntireWorkArea() {
        let layout = DeckLayout()
        let result = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: 1, params: params()))

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0], workArea)
    }

    func testTwoWindows_DefaultNmaster1_MasterGetsMfactWidth_StackGetsFullStackRect() {
        let layout = DeckLayout()
        let result = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: 2, params: params(nmaster: 1, mfact: 0.55)))

        XCTAssertEqual(result.count, 2)

        let expectedMasterWidth = Self.roundedWidth(workArea.width, 0.55)
        XCTAssertEqual(result[0].x, workArea.x)
        XCTAssertEqual(result[0].width, expectedMasterWidth)
        XCTAssertEqual(result[0].height, workArea.height)

        XCTAssertEqual(result[1].x, workArea.x + expectedMasterWidth)
        XCTAssertEqual(result[1].width, workArea.width - expectedMasterWidth)
        XCTAssertEqual(result[1].height, workArea.height)
    }

    func testThreeWindows_Nmaster1_AllStackWindowsShareIdenticalRect() {
        let layout = DeckLayout()
        let result = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: 3, params: params(nmaster: 1)))

        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[2], result[1]) // deck-style overlap, not stacked rows
    }

    func testFiveWindows_Nmaster2_AllThreeStackWindowsShareIdenticalRect() {
        let layout = DeckLayout()
        let result = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: 5, params: params(nmaster: 2)))

        XCTAssertEqual(result.count, 5)
        XCTAssertEqual(result[3], result[2])
        XCTAssertEqual(result[4], result[2])
    }

    func testNmasterCoversAllWindows_MastersAreSideBySideColumns_NoStack() {
        let layout = DeckLayout()
        let result = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: 2, params: params(nmaster: 5)))

        for r in result {
            XCTAssertEqual(r.height, workArea.height)
        }
        XCTAssertEqual(result[0].width + result[1].width, workArea.width)
        XCTAssertEqual(result[1].x, result[0].x + result[0].width)
    }

    func testThreeWindows_Nmaster2_MasterColumnsSideBySide_LoneStackGetsFullStackRect() {
        let layout = DeckLayout()
        let result = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: 3, params: params(nmaster: 2, mfact: 0.5)))

        XCTAssertEqual(result[0].height, workArea.height)
        XCTAssertEqual(result[1].height, workArea.height)
        XCTAssertEqual(result[1].width, result[0].width)
        XCTAssertEqual(result[1].x, result[0].x + result[0].width) // side by side

        XCTAssertEqual(result[2].x, result[1].x + result[1].width)
        XCTAssertEqual(result[2].height, workArea.height)
    }

    func testNmasterZero_AllWindowsShareFullWorkAreaAsStack() {
        let layout = DeckLayout()
        let result = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: 3, params: params(nmaster: 0)))

        XCTAssertEqual(result.count, 3)
        for r in result {
            XCTAssertEqual(r, workArea)
        }
    }

    func testGap_InsetsMasterColumnAndStackRectConsistently() {
        let layout = DeckLayout()
        let gap = 10
        let noGap = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: 3, params: params(nmaster: 1, gap: 0)))
        let withGap = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: 3, params: params(nmaster: 1, gap: gap)))

        XCTAssertEqual(withGap.count, noGap.count)
        for i in 0..<noGap.count {
            XCTAssertEqual(withGap[i].x, noGap[i].x + gap / 2)
            XCTAssertEqual(withGap[i].y, noGap[i].y + gap / 2)
            XCTAssertEqual(withGap[i].width, noGap[i].width - gap)
            XCTAssertEqual(withGap[i].height, noGap[i].height - gap)
        }
    }

    func testMasterColumnsNeverOverlapEachOtherOrStackRect_ForVariousWindowCounts() {
        let layout = DeckLayout()
        for n in 1...8 {
            let result = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: n, params: params(nmaster: 2)))
            let masterCount = min(n, 2)

            // Master columns pairwise disjoint, and disjoint from every stack rect.
            for i in 0..<masterCount {
                for j in (i + 1)..<result.count {
                    XCTAssertFalse(Self.overlaps(result[i], result[j]), "n=\(n): rect \(i) overlaps rect \(j)")
                }
            }

            // Stack rects, if any, must all be equal to each other (intended overlap).
            for i in masterCount..<result.count {
                XCTAssertEqual(result[i], result[masterCount])
            }
        }
    }
}