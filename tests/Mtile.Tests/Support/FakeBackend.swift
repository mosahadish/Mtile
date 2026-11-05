@testable import Mtile

/// In-memory WindowBackend: windows are just frames in a dictionary, so WindowManager's tag,
/// parking and focus logic can be exercised without a Mac (or a screen).
final class FakeBackend: WindowBackend {
    var monitorInfos: [MonitorInfo]
    var snapshots: [WindowID: WindowSnapshot] = [:]
    var order: [WindowID] = []
    var focused: WindowID?
    var refuseSetFrame: Set<WindowID> = []
    private(set) var focusCalls: [WindowID] = []
    private(set) var focusNothingCalls = 0
    private(set) var closed: [WindowID] = []
    private(set) var terminated: [WindowID] = []

    static let primary = MonitorInfo(displayID: 1, isPrimary: true,
                                     frame: LayoutRect(x: 0, y: 0, width: 1440, height: 900),
                                     workArea: LayoutRect(x: 0, y: 25, width: 1440, height: 875))

    init(monitors: [MonitorInfo] = [FakeBackend.primary]) {
        monitorInfos = monitors
    }

    @discardableResult
    func addWindow(_ id: WindowID, app: String = "Safari", pid: Int32 = 100, title: String? = nil,
                   frame: LayoutRect = LayoutRect(x: 100, y: 100, width: 800, height: 600),
                   className: String = "AXStandardWindow", manageable: Bool = true) -> WindowID {
        snapshots[id] = WindowSnapshot(pid: pid, title: title ?? "\(app) \(id)", className: className,
                                       processNameAliases: WindowSnapshot.aliases(appName: app, bundleID: "com.example.\(app.lowercased())", executableName: app),
                                       frame: frame, isManageable: manageable)
        order.append(id)
        return id
    }

    func removeWindow(_ id: WindowID) {
        snapshots[id] = nil
        order.removeAll { $0 == id }
    }

    func frameOf(_ id: WindowID) -> LayoutRect? { snapshots[id]?.frame }

    // MARK: WindowBackend

    func monitors() -> [MonitorInfo] { monitorInfos }
    func allWindows() -> [WindowID] { order }
    func focusedWindow() -> WindowID? { focused }
    func describe(_ id: WindowID) -> WindowSnapshot? { snapshots[id] }
    func title(_ id: WindowID) -> String { snapshots[id]?.title ?? "" }
    func frame(_ id: WindowID) -> LayoutRect? { snapshots[id]?.frame }

    func setFrame(_ id: WindowID, _ rect: LayoutRect) -> Bool {
        guard snapshots[id] != nil, !refuseSetFrame.contains(id) else { return false }
        snapshots[id]?.frame = rect
        return true
    }

    func focus(_ id: WindowID) {
        focused = id
        focusCalls.append(id)
    }

    func focusNothing() {
        focused = nil
        focusNothingCalls += 1
    }

    func close(_ id: WindowID) { closed.append(id) }
    func terminateOwner(_ id: WindowID) { terminated.append(id) }
    func cursorPosition() -> (x: Int, y: Int) { (0, 0) }
}

/// Controllable clock for WindowManager's "ignore focus echoes for 0.5 s" window.
final class FakeClock {
    var now = 1000.0
}
