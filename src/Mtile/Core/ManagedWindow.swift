public final class ManagedWindow {
    public let id: WindowID
    public let pid: Int32
    public var title = ""
    /// AXSubrole on macOS (e.g. "AXStandardWindow"); plays the role of Wtile's window class.
    public var className = ""
    /// Every name the owning app is known by -- see `WindowSnapshot.processNameAliases`.
    public var processNames: [String] = []
    public var isMinimized = false
    public var isFloating = false
    public var isPinned = false
    public var tagIndex = 0
    public var monitorIndex = 0
    /// The app itself is hidden (Cmd+H); unlike Mtile's own tag hiding, nothing to undo.
    public var isHiddenByApp = false

    /// Where the window was when Mtile parked it off-screen for a tag switch (nil while it's
    /// not parked). Restored on show, so floating windows come back exactly where they were.
    public var parkedFrom: LayoutRect?
    public var isParked: Bool { parkedFrom != nil }

    public init(id: WindowID, pid: Int32) {
        self.id = id
        self.pid = pid
    }
}
