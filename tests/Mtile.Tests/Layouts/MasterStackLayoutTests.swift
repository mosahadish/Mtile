// Port of tests/Wtile.Tests/Layouts/MasterStackLayoutTests.cs
import XCTest
@testable import Mtile

final class MasterStackLayoutTests: XCTestCase {
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

    func testNoWindows_ReturnsEmpty() {
        let layout = MasterStackLayout()
        let result = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: 0, params: params()))
        XCTAssertTrue(result.isEmpty)
    }

    func testSingleWindow_FillsEntireWorkArea() {
        let layout = MasterStackLayout()
        let result = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: 1, params: params()))

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0], workArea)
    }

    func testTwoWindows_DefaultNmaster1_SplitsByMfact() {
        let layout = MasterStackLayout()
        let result = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: 2, params: params(nmaster: 1, mfact: 0.55)))

        XCTAssertEqual(result.count, 2)

        let master = result[0]
        let stack = result[1]

        let expectedMasterWidth = Self.roundedWidth(workArea.width, 0.55)
        XCTAssertEqual(master.x, workArea.x)
        XCTAssertEqual(master.y, workArea.y)
        XCTAssertEqual(master.width, expectedMasterWidth)
        XCTAssertEqual(master.height, workArea.height)

        XCTAssertEqual(stack.x, workArea.x + expectedMasterWidth)
        XCTAssertEqual(stack.y, workArea.y)
        XCTAssertEqual(stack.width, workArea.width - expectedMasterWidth)
        XCTAssertEqual(stack.height, workArea.height)
    }

    func testThreeWindows_Nmaster1_StacksTwoInStackColumn() {
        let layout = MasterStackLayout()
        let result = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: 3, params: params(nmaster: 1)))

        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].height, workArea.height)

        XCTAssertEqual(result[2].x, result[1].x)
        XCTAssertEqual(result[2].width, result[1].width)
        XCTAssertEqual(result[2].y, result[1].y + result[1].height)
        XCTAssertEqual(result[1].height + result[2].height, workArea.height)
    }

    func testNmasterCoversAllWindows_MastersAreSideBySideColumns() {
        let layout = MasterStackLayout()
        let result = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: 2, params: params(nmaster: 5)))

        for r in result {
            XCTAssertEqual(r.height, workArea.height)
        }
        XCTAssertEqual(result[0].width + result[1].width, workArea.width)
        XCTAssertEqual(result[1].x, result[0].x + result[0].width)
    }

    func testThreeWindows_Nmaster2_MasterColumnsAreSideBySide_NotStacked() {
        let layout = MasterStackLayout()
        let result = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: 3, params: params(nmaster: 2, mfact: 0.5)))

        XCTAssertEqual(result[0].height, workArea.height)
        XCTAssertEqual(result[1].height, workArea.height)
        XCTAssertEqual(result[1].width, result[0].width)
        XCTAssertEqual(result[1].x, result[0].x + result[0].width)

        XCTAssertEqual(result[2].x, result[1].x + result[1].width)
        XCTAssertEqual(result[2].height, workArea.height)
    }

    func testMasterOnRight_ThreeWindows_Nmaster2_MatchesBugNExample() {
        let layout = MasterStackLayout(masterOnRight: true)
        let result = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: 3, params: params(nmaster: 2, mfact: 0.5)))

        XCTAssertEqual(result[2].x, workArea.x) // stack window is leftmost
        XCTAssertEqual(result[0].x, result[2].x + result[2].width)
        XCTAssertEqual(result[1].x, result[0].x + result[0].width)
        XCTAssertEqual(result[0].height, workArea.height)
        XCTAssertEqual(result[1].height, workArea.height)
    }

    func testNmasterZero_AllWindowsInStackColumn_FillsFullWidth() {
        let layout = MasterStackLayout()
        let result = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: 2, params: params(nmaster: 0)))

        for r in result {
            XCTAssertEqual(r.x, workArea.x)
            XCTAssertEqual(r.width, workArea.width)
        }
    }

    func testGap_InsetsEveryRectOnAllSides() {
        let layout = MasterStackLayout()
        let gap = 10
        let noGap = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: 2, params: params(gap: 0)))
        let withGap = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: 2, params: params(gap: gap)))

        XCTAssertEqual(withGap.count, noGap.count)
        for i in 0..<noGap.count {
            XCTAssertEqual(withGap[i].x, noGap[i].x + gap / 2)
            XCTAssertEqual(withGap[i].y, noGap[i].y + gap / 2)
            XCTAssertEqual(withGap[i].width, noGap[i].width - gap)
            XCTAssertEqual(withGap[i].height, noGap[i].height - gap)
        }
    }

    func testRectanglesNeverOverlap_ForVariousWindowCounts() {
        let layout = MasterStackLayout()
        for n in 1...8 {
            let result = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: n, params: params(nmaster: 2)))
            for i in 0..<result.count {
                for j in (i + 1)..<result.count {
                    XCTAssertFalse(Self.overlaps(result[i], result[j]), "n=\(n): rect \(i) overlaps rect \(j)")
                }
            }
        }
    }

    func testMasterOnRight_HasDistinctNameAndSymbol() {
        let layout = MasterStackLayout(masterOnRight: true)
        XCTAssertEqual(layout.name, "master-stack-right")
        XCTAssertEqual(layout.symbol, "=[]")
        XCTAssertEqual(MasterStackLayout().name, "master-stack")
        XCTAssertEqual(MasterStackLayout().symbol, "[]=")
    }

    func testMasterOnRight_TwoWindows_MasterIsOnTheRightSide() {
        let layout = MasterStackLayout(masterOnRight: true)
        let result = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: 2, params: params(nmaster: 1, mfact: 0.55)))

        let expectedMasterWidth = Self.roundedWidth(workArea.width, 0.55)
        let master = result[0] // index 0 is always master, regardless of which side it renders on
        let stack = result[1]

        XCTAssertEqual(stack.x, workArea.x)
        XCTAssertEqual(stack.width, workArea.width - expectedMasterWidth)
        XCTAssertEqual(master.x, workArea.x + stack.width)
        XCTAssertEqual(master.width, expectedMasterWidth)
    }

    func testMasterOnRight_SingleWindow_StillFillsEntireWorkArea() {
        let layout = MasterStackLayout(masterOnRight: true)
        let result = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: 1, params: params()))

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0], workArea)
    }
}