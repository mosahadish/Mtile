import XCTest
@testable import Mtile

/// WindowManager behaviour driven through FakeBackend. Layout: master-stack, nmaster 1,
/// mfact 0.5, no gap, on a 1440x900 screen whose work area (below the menu bar) is
/// (0, 25, 1440x875) -- so one window fills the work area and two split it at x = 720.
final class WindowManagerTests: XCTestCase {
    private var backend: FakeBackend!
    private var clock: FakeClock!

    private let work = LayoutRect(x: 0, y: 25, width: 1440, height: 875)
    private let left = LayoutRect(x: 0, y: 25, width: 720, height: 875)
    private let right = LayoutRect(x: 720, y: 25, width: 720, height: 875)
    /// Bottom-right park corner of the primary monitor for an 800x600 window.
    private let parked = LayoutRect(x: 1439, y: 899, width: 800, height: 600)

    override func setUp() {
        super.setUp()
        backend = FakeBackend()
        clock = FakeClock()
    }

    private func makeManager(newIsMaster: Bool = true, tagCount: Int = 9) -> WindowManager {
        let clock = self.clock!
        let manager = WindowManager(backend: backend, layouts: LayoutRegistry.createDefault(), defaultLayoutName: "master-stack",
                                    defaultLayoutParams: ["nmaster": 1, "mfact": 0.5, "gap": 0], tagCount: tagCount,
                                    clock: { clock.now })
        manager.setNewIsMaster(newIsMaster)
        manager.initializeMonitors()
        return manager
    }

    private func managedIDs(_ manager: WindowManager) -> [WindowID] { manager.windows.map(\.id) }

    // MARK: - Adoption

    func testSeed_AdoptsManageableWindowsAndTilesThem() {
        backend.addWindow(1)
        backend.addWindow(2)
        backend.addWindow(3, manageable: false)
        let manager = makeManager()

        manager.seed()

        XCTAssertEqual(Set(managedIDs(manager)), [1, 2])
        XCTAssertEqual(frames(1, 2), [left, right])
        XCTAssertEqual(backend.frameOf(3), LayoutRect(x: 100, y: 100, width: 800, height: 600))
    }

    func testSingleWindow_FillsWorkAreaMinusBarInset() {
        backend.addWindow(1)
        let manager = makeManager()
        manager.setBarInsets(monitorIndex: 0, top: 24, bottom: 0)

        manager.seed()

        XCTAssertEqual(backend.frameOf(1), LayoutRect(x: 0, y: 49, width: 1440, height: 851))
    }

    func testNewIsMaster_NewWindowTakesMasterSlot() {
        backend.addWindow(1)
        let manager = makeManager(newIsMaster: true)
        manager.seed()

        backend.addWindow(2)
        manager.onWindowCreated(2)

        XCTAssertEqual(backend.frameOf(2), left)
        XCTAssertEqual(backend.frameOf(1), right)
        XCTAssertEqual(manager.focusedID, 2)
    }

    func testNewIsMasterFalse_NewWindowAttachesAfterMaster() {
        backend.addWindow(1)
        let manager = makeManager(newIsMaster: false)
        manager.seed()

        backend.addWindow(2)
        manager.onWindowCreated(2)

        XCTAssertEqual(backend.frameOf(1), left)
        XCTAssertEqual(backend.frameOf(2), right)
    }

    func testBlacklistedWindow_IsNotManaged() {
        backend.addWindow(1, app: "Steam")
        let manager = makeManager()
        manager.setBlacklist(WindowRuleCompiler.compileBlacklist([rule(processName: "^steam\\.exe$")]))

        manager.seed()

        XCTAssertTrue(manager.windows.isEmpty)
    }

    func testTagRule_PlacesWindowOnItsTagParked() {
        let manager = makeManager()
        manager.setTagRules(WindowRuleCompiler.compileTagRules([tagRule(processName: "^firefox\\.exe$", tag: 3)]))

        backend.addWindow(1, app: "Firefox")
        manager.onWindowCreated(1)

        XCTAssertEqual(manager.windows.first?.tagIndex, 2)
        XCTAssertEqual(manager.monitors[0].activeTagIndex, 0)
        XCTAssertEqual(backend.frameOf(1), parked)
    }

    func testTagRuleWithFollow_SwitchesToTheTag() {
        let manager = makeManager()
        manager.setTagRules(WindowRuleCompiler.compileTagRules([tagRule(processName: "Firefox", tag: 3, follow: true)]))

        backend.addWindow(1, app: "Firefox")
        manager.onWindowCreated(1)

        XCTAssertEqual(manager.monitors[0].activeTagIndex, 2)
        XCTAssertEqual(backend.frameOf(1), work)
    }

    // MARK: - Tags and parking

    func testActivateTag_ParksOldTagAndRestoresOnReturn() {
        backend.addWindow(1)
        backend.addWindow(2)
        let manager = makeManager()
        manager.seed()
        let before = [backend.frameOf(1), backend.frameOf(2)]

        manager.activateTag(1)

        for id: WindowID in [1, 2] {
            let frame = backend.frameOf(id)!
            XCTAssertEqual(frame.x, 1439, "window \(id) should hang off the right edge")
            XCTAssertEqual(frame.y, 899, "window \(id) should hang off the bottom edge")
            XCTAssertTrue(manager.windows.first { $0.id == id }!.isParked)
        }
        XCTAssertNil(manager.focusedID)
        XCTAssertEqual(backend.focusNothingCalls, 1)

        manager.activateTag(0)

        XCTAssertEqual([backend.frameOf(1), backend.frameOf(2)], before)
        XCTAssertFalse(manager.windows.contains { $0.isParked })
    }

    func testMoveWindowToTag_ParksItAndRetilesTheRest() {
        backend.addWindow(1)
        backend.addWindow(2)
        let manager = makeManager()
        manager.seed()
        manager.onFocusChanged(1)

        manager.moveWindowToTag(4)

        XCTAssertEqual(manager.windows.first { $0.id == 1 }?.tagIndex, 4)
        XCTAssertEqual(backend.frameOf(1)?.y, 899)
        XCTAssertEqual(backend.frameOf(2), work)
        XCTAssertEqual(manager.focusedID, 2)
        XCTAssertTrue(manager.hasWindowsOnTag(monitorIndex: 0, tagIndex: 4))
    }

    func testToggleLastTag_ReturnsToPreviousTag() {
        let manager = makeManager()
        manager.activateTag(3)
        manager.activateTag(5)

        manager.toggleLastTag()

        XCTAssertEqual(manager.monitors[0].activeTagIndex, 3)
    }

    func testViewAllTags_ShowsEveryWindowOnTheMonitor() {
        backend.addWindow(1)
        backend.addWindow(2)
        let manager = makeManager()
        manager.seed()
        manager.onFocusChanged(1)
        manager.moveWindowToTag(2)

        manager.viewAllTags()

        XCTAssertFalse(manager.windows.contains { $0.isParked })
        XCTAssertEqual(frames(1, 2), [left, right])
    }

    func testPinnedWindow_StaysVisibleAcrossTagSwitches() {
        backend.addWindow(1)
        let manager = makeManager()
        manager.seed()
        manager.onFocusChanged(1)
        manager.togglePinned()

        manager.activateTag(6)

        XCTAssertEqual(backend.frameOf(1), work)
    }

    func testRestoreAllWindows_UnparksEverything() {
        backend.addWindow(1)
        let manager = makeManager()
        manager.seed()
        let tiled = backend.frameOf(1)
        manager.activateTag(1)

        manager.restoreAllWindows()

        XCTAssertEqual(backend.frameOf(1), tiled)
    }

    func testUnmanagedWindowLeftParkedByPreviousRun_IsRecovered() {
        backend.addWindow(1, frame: parked, manageable: false)
        let manager = makeManager()

        manager.seed()

        let frame = backend.frameOf(1)!
        XCTAssertEqual(frame, LayoutRect(x: 320, y: 162, width: 800, height: 600))
    }

    // MARK: - Focus

    func testFocusOnParkedWindow_FollowsItToItsTag() {
        backend.addWindow(1)
        backend.addWindow(2)
        let manager = makeManager()
        manager.seed()
        manager.onFocusChanged(1)
        manager.moveWindowToTag(3)
        clock.now += 1 // past the echo-suppression window

        manager.onFocusChanged(1) // e.g. Cmd+Tab to that app

        XCTAssertEqual(manager.monitors[0].activeTagIndex, 3)
        XCTAssertEqual(manager.focusedID, 1)
        XCTAssertEqual(backend.frameOf(1), work)
    }

    func testFocusEchoRightAfterTagSwitch_DoesNotFollow() {
        backend.addWindow(1)
        backend.addWindow(2)
        let manager = makeManager()
        manager.seed()
        manager.onFocusChanged(1)
        manager.moveWindowToTag(3)

        manager.onFocusChanged(1) // arrives within 0.5 s of Mtile's own move

        XCTAssertEqual(manager.monitors[0].activeTagIndex, 0)
    }

    func testFocusNext_CyclesThroughVisibleWindows() {
        backend.addWindow(1)
        backend.addWindow(2)
        backend.addWindow(3)
        let manager = makeManager()
        manager.seed()
        let order = managedIDs(manager)
        manager.onFocusChanged(order[0])

        manager.focusNext()
        XCTAssertEqual(manager.focusedID, order[1])
        manager.focusNext()
        manager.focusNext()
        XCTAssertEqual(manager.focusedID, order[0])
        manager.focusPrev()
        XCTAssertEqual(manager.focusedID, order[2])
    }

    func testDestroyingFocusedWindow_FocusesAnother() {
        backend.addWindow(1)
        backend.addWindow(2)
        let manager = makeManager()
        manager.seed()
        manager.onFocusChanged(1)

        backend.removeWindow(1)
        manager.onWindowDestroyed(1)

        XCTAssertEqual(managedIDs(manager), [2])
        XCTAssertEqual(manager.focusedID, 2)
        XCTAssertEqual(backend.frameOf(2), work)
    }

    // MARK: - Robustness

    func testWindowRefusingToMove_IsFloated() {
        backend.addWindow(1)
        backend.addWindow(2)
        backend.refuseSetFrame = [2]
        let manager = makeManager()

        manager.seed()

        XCTAssertTrue(manager.windows.first { $0.id == 2 }!.isFloating)
        XCTAssertEqual(backend.frameOf(1), work)
    }

    func testResync_AdoptsMissedAndDropsVanishedWindows() {
        backend.addWindow(1)
        backend.addWindow(2)
        let manager = makeManager()
        manager.seed()

        backend.removeWindow(1) // destroyed without a notification
        backend.addWindow(3)    // created without a notification
        manager.resync()

        XCTAssertEqual(Set(managedIDs(manager)), [2, 3])
    }

    func testHiddenApp_IsRemovedFromTilingUntilUnhidden() {
        backend.addWindow(1, pid: 10)
        backend.addWindow(2, pid: 20)
        let manager = makeManager()
        manager.seed()

        manager.onAppHiddenChanged(pid: 20, hidden: true)
        XCTAssertEqual(backend.frameOf(1), work)

        manager.onAppHiddenChanged(pid: 20, hidden: false)
        XCTAssertEqual(frames(1, 2), [left, right])
    }

    func testAdjustMfact_IsSignFlippedForMasterStackRight() {
        backend.addWindow(1)
        backend.addWindow(2)
        let manager = makeManager()
        manager.seed()
        manager.setLayout("master-stack-right")

        manager.adjustMfact(0.1)

        XCTAssertEqual(manager.monitors[0].tags[0].layoutParams["mfact"]!, 0.4, accuracy: 1e-9)
    }

    func testUpdateTagCount_ClampsWindowsOnRemovedTags() {
        backend.addWindow(1)
        let manager = makeManager()
        manager.seed()
        manager.onFocusChanged(1)
        manager.moveWindowToTag(8)

        manager.updateTagCount(4)

        XCTAssertEqual(manager.tagCount, 4)
        XCTAssertEqual(manager.windows.first?.tagIndex, 3)
        XCTAssertEqual(manager.monitors[0].tags.count, 4)
    }

    // MARK: - Multiple monitors

    private let external = MonitorInfo(displayID: 2, isPrimary: false,
                                       frame: LayoutRect(x: 1440, y: 0, width: 1920, height: 1080),
                                       workArea: LayoutRect(x: 1440, y: 0, width: 1920, height: 1080))

    func testParkRect_UsesTheCornerThatDoesNotBorderAnotherMonitor() {
        backend = FakeBackend(monitors: [FakeBackend.primary, external])
        backend.addWindow(1)
        let manager = makeManager()
        manager.seed()

        manager.activateTag(1)

        // The primary's right edge touches the external display, so park bottom-left instead
        // (keeping the tiled size it had, 1440x875).
        XCTAssertEqual(backend.frameOf(1), LayoutRect(x: -1439, y: 899, width: 1440, height: 875))
    }

    func testRefreshMonitors_MovesWindowsOffADisconnectedDisplay() {
        backend = FakeBackend(monitors: [FakeBackend.primary, external])
        backend.addWindow(1, frame: LayoutRect(x: 1600, y: 100, width: 800, height: 600))
        let manager = makeManager()
        manager.seed()
        XCTAssertEqual(manager.windows.first?.monitorIndex, 1)

        backend.monitorInfos = [FakeBackend.primary]
        let countChanged = manager.refreshMonitors()

        XCTAssertTrue(countChanged)
        XCTAssertEqual(manager.windows.first?.monitorIndex, 0)
        XCTAssertEqual(backend.frameOf(1), work)
    }

    // MARK: - Helpers

    private func frames(_ ids: WindowID...) -> Set<LayoutRect> { Set(ids.compactMap { backend.frameOf($0) }) }

    private func rule(processName: String) -> BlacklistRule {
        var r = BlacklistRule()
        r.processName = processName
        return r
    }

    private func tagRule(processName: String, tag: Int, follow: Bool = false) -> TagRule {
        var r = TagRule()
        r.processName = processName
        r.tag = tag
        r.follow = follow
        return r
    }
}
