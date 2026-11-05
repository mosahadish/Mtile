/// Opaque, process-lifetime-stable window identity handed out by the backend.
public typealias WindowID = UInt64

/// What WindowManager needs to know about a window when deciding whether/how to manage it.
public struct WindowSnapshot {
    public var pid: Int32
    public var title: String
    /// AXSubrole on macOS ("AXStandardWindow", "AXDialog", ...).
    public var className: String
    /// The localized app name, bundle identifier and executable name, plus each with ".exe"
    /// appended, so a Windows-flavoured processName regex (e.g. "^firefox\.exe$") written for
    /// Wtile still matches the same app on macOS.
    public var processNameAliases: [String]
    public var frame: LayoutRect
    public var isMinimized: Bool
    public var isAppHidden: Bool
    /// Normal, resizable top-level window (not a sheet, popover, tooltip, panel, ...).
    public var isManageable: Bool

    public init(pid: Int32, title: String, className: String, processNameAliases: [String], frame: LayoutRect,
                isMinimized: Bool = false, isAppHidden: Bool = false, isManageable: Bool = true) {
        self.pid = pid
        self.title = title
        self.className = className
        self.processNameAliases = processNameAliases
        self.frame = frame
        self.isMinimized = isMinimized
        self.isAppHidden = isAppHidden
        self.isManageable = isManageable
    }

    public static func aliases(appName: String, bundleID: String, executableName: String) -> [String] {
        var names: [String] = []
        for name in [appName, bundleID, executableName] where !name.isEmpty {
            if !names.contains(name) { names.append(name) }
            if !names.contains(name + ".exe") { names.append(name + ".exe") }
        }
        return names
    }
}

public struct MonitorInfo: Equatable {
    public var displayID: UInt32
    public var isPrimary: Bool
    public var frame: LayoutRect
    public var workArea: LayoutRect

    public init(displayID: UInt32, isPrimary: Bool, frame: LayoutRect, workArea: LayoutRect) {
        self.displayID = displayID
        self.isPrimary = isPrimary
        self.frame = frame
        self.workArea = workArea
    }
}

/// Every OS operation WindowManager performs, so the manager's tag/stack/focus logic is plain
/// Swift that unit tests drive with a fake backend. The macOS implementation is WindowInspector
/// (Accessibility API); Wtile calls Win32 directly from its WindowManager instead.
public protocol WindowBackend: AnyObject {
    func monitors() -> [MonitorInfo]
    /// Every window currently on screen (or minimized) across all running regular apps.
    func allWindows() -> [WindowID]
    func focusedWindow() -> WindowID?
    func describe(_ id: WindowID) -> WindowSnapshot?
    func title(_ id: WindowID) -> String
    func frame(_ id: WindowID) -> LayoutRect?
    /// Returns false if the window refused (non-resizable, gone, app not responding).
    @discardableResult func setFrame(_ id: WindowID, _ rect: LayoutRect) -> Bool
    func focus(_ id: WindowID)
    /// Called when nothing is left to focus on the current monitor.
    func focusNothing()
    func close(_ id: WindowID)
    func terminateOwner(_ id: WindowID)
    func cursorPosition() -> (x: Int, y: Int)
}
