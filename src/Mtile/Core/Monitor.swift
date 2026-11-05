/// A connected display's own tag/layout state (dwm's per-monitor struct). Geometry is refreshed
/// from the backend on every arrange/refresh, in Accessibility coordinates.
public final class Monitor {
    /// Stable display identifier from the backend (CGDirectDisplayID on macOS). nil while this
    /// monitor is disconnected, in which case arranging it is skipped.
    public var displayID: UInt32?
    public var isPrimary: Bool
    public var frame: LayoutRect
    /// Frame minus the menu bar and Dock.
    public var workArea: LayoutRect
    public var tags: [Tag]
    public var activeTagIndex = 0
    public var previousTagIndex = 0
    /// dwm's view(~0), scoped to this monitor.
    public var isViewingAllTags = false
    /// Points this monitor's own Mtile bar reserves at the top/bottom of its work area.
    public var reservedTopInset = 0
    public var reservedBottomInset = 0

    public init(displayID: UInt32?, isPrimary: Bool, frame: LayoutRect, workArea: LayoutRect, tags: [Tag]) {
        self.displayID = displayID
        self.isPrimary = isPrimary
        self.frame = frame
        self.workArea = workArea
        self.tags = tags
    }
}
