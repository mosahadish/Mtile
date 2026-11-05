// Port of tests/Wtile.Tests/Layouts/CenteredMasterLayoutTests.cs
import XCTest
@testable import Mtile

final class CenteredMasterLayoutTests: XCTestCase {
    private let workArea = LayoutRect(x: 0, y: 24, width: 1920, height: 1056)

    private func params(nmaster: Int = 1, mfact: Double = 0.5, gap: Int = 0) -> [String: Double] {
        ["nmaster": Double(nmaster), "mfact": mfact, "gap": Double(gap)]
    }

    private static func roundedWidth(_ width: Int, _ fraction: Double) -> Int {
        Int((Double(width) * fraction).rounded(.toNearestOrEven))
    }

    private static func overlaps(_ a: LayoutRect, _ b: LayoutRect) -> Bool {
        a.x < b.x + b.width && a.x + a.width > b.x && a.y < b.y + b.height && a.y + a.height > b.y
    }

    func testNameAndSymbol() {
        let layout = CenteredMasterLayout()
        XCTAssertEqual(layout.name, "centered-master")
        XCTAssertEqual(layout.symbol, "|M|")
    }

    func testNoWindows_ReturnsEmpty() {
        let layout = CenteredMasterLayout()
        XCTAssertTrue(layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: 0, params: params())).isEmpty)
    }

    func testSingleWindow_IsHorizontallyCenteredWithFullHeight() {
        let layout = CenteredMasterLayout()
        let result = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: 1, params: params(mfact: 0.5)))

        XCTAssertEqual(result.count, 1)
        let r = result[0]

        let expectedWidth = Self.roundedWidth(workArea.width, 0.5)
        XCTAssertEqual(r.width, expectedWidth)
        XCTAssertEqual(r.height, workArea.height) // full height -- not vertically centered
        XCTAssertEqual(r.y, workArea.y)

        // Centered horizontally -- not stretched fullscreen like master-stack/monocle would.
        XCTAssertNotEqual(r.width, workArea.width)
        XCTAssertEqual(r.x, workArea.x + (workArea.width - expectedWidth) / 2)
    }

    func testTwoWindows_MasterCentered_FirstStackGoesRight() {
        let layout = CenteredMasterLayout()
        let result = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: 2, params: params(nmaster: 1, mfact: 0.5)))

        let expectedMasterWidth = Self.roundedWidth(workArea.width, 0.5)
        let sideWidth = (workArea.width - expectedMasterWidth) / 2

        let master = result[0]
        let stack = result[1]

        XCTAssertEqual(master.x, workArea.x + sideWidth)
        XCTAssertEqual(master.width, expectedMasterWidth)
        XCTAssertEqual(master.height, workArea.height)

        // First (and only) stack window goes to the right of master.
        XCTAssertEqual(stack.x, master.x + master.width)
        XCTAssertEqual(stack.width, sideWidth)
        XCTAssertEqual(stack.height, workArea.height)
    }

    func testFiveWindows_Nmaster1_StackAlternatesRightThenLeft() {
        let layout = CenteredMasterLayout()
        let result = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: 5, params: params(nmaster: 1, mfact: 0.5)))

        XCTAssertEqual(result.count, 5)

        let expectedMasterWidth = Self.roundedWidth(workArea.width, 0.5)
        let sideWidth = (workArea.width - expectedMasterWidth) / 2
        let masterX = workArea.x + sideWidth
        let rightX = masterX + expectedMasterWidth
        let leftX = workArea.x

        // index 0 = master; 1,3 = right (2 windows sharing the right column); 2,4 = left.
        XCTAssertEqual(result[0].x, masterX)
        XCTAssertEqual(result[1].x, rightX)
        XCTAssertEqual(result[2].x, leftX)
        XCTAssertEqual(result[3].x, rightX)
        XCTAssertEqual(result[4].x, leftX)

        XCTAssertEqual(result[1].height + result[3].height, workArea.height)
        XCTAssertEqual(result[2].height + result[4].height, workArea.height)
    }

    func testNoStack_MasterFillsFullWidth() {
        let layout = CenteredMasterLayout()
        let result = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: 2, params: params(nmaster: 5)))

        for r in result {
            XCTAssertEqual(r.width, workArea.width)
        }
        XCTAssertEqual(result[0].height + result[1].height, workArea.height)
    }

    func testRectanglesNeverOverlap_ForVariousWindowCounts() {
        let layout = CenteredMasterLayout()
        for n in 1...8 {
            let result = layout.arrange(LayoutContext(workArea: workArea, tiledWindowCount: n, params: params(nmaster: 2)))
            for i in 0..<result.count {
                for j in (i + 1)..<result.count {
                    XCTAssertFalse(Self.overlaps(result[i], result[j]), "n=\(n): rect \(i) overlaps rect \(j)")
                }
            }
        }
    }
}