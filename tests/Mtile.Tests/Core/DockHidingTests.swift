import XCTest
@testable import Mtile

final class DockHidingTests: XCTestCase {
    func testIsHidden_RequiresAutohideAndHugeDelay() {
        XCTAssertTrue(DockHiding.isHidden(autohide: true, autohideDelay: DockHiding.revealDelay))
        XCTAssertFalse(DockHiding.isHidden(autohide: true, autohideDelay: nil))
        XCTAssertFalse(DockHiding.isHidden(autohide: true, autohideDelay: 0.5))
        XCTAssertFalse(DockHiding.isHidden(autohide: false, autohideDelay: DockHiding.revealDelay))
        XCTAssertFalse(DockHiding.isHidden(autohide: nil, autohideDelay: nil))
    }

    func testWorkArea_BottomDock_ReclaimsBottomKeepsMenuBar() {
        let frame = LayoutRect(x: 0, y: 0, width: 1512, height: 982)
        let visible = LayoutRect(x: 0, y: 37, width: 1512, height: 870)
        XCTAssertEqual(DockHiding.workArea(frame: frame, visible: visible), LayoutRect(x: 0, y: 37, width: 1512, height: 945))
    }

    func testWorkArea_SideDock_ReclaimsSide() {
        let frame = LayoutRect(x: 1512, y: -200, width: 1920, height: 1080)
        let visible = LayoutRect(x: 1512 + 64, y: -175, width: 1920 - 64, height: 1055)
        XCTAssertEqual(DockHiding.workArea(frame: frame, visible: visible), LayoutRect(x: 1512, y: -175, width: 1920, height: 1055))
    }

    func testSavedSettings_RoundTripKeepsUnsetKeys() throws {
        let saved = SavedDockSettings(autohide: nil, autohideDelay: 0.2)
        let decoded = try JSONDecoder().decode(SavedDockSettings.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(decoded, saved)
    }
}
