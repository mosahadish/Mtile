/// Clickable tag pills for one monitor's bar, dwm-style: active tag highlighted, empty tags
/// dimmed. An occupied-but-not-active tag gets either a small corner marker (default) or a filled
/// background (`occupiedTagIndicator: background`), never both. Same as Wtile's TagsSegment.
public final class TagsSegment: Segment {
    static let tagWidth = 28.0
    static let markerSize = 4.0
    static let markerInset = 3.0

    private let manager: WindowManager
    private let commands: CommandRegistry
    private let theme: BarTheme
    private let monitorIndex: Int
    private let useBackgroundIndicator: Bool

    public init(manager: WindowManager, commands: CommandRegistry, theme: BarTheme, monitorIndex: Int, useBackgroundIndicator: Bool) {
        self.manager = manager
        self.commands = commands
        self.theme = theme
        self.monitorIndex = monitorIndex
        self.useBackgroundIndicator = useBackgroundIndicator
    }

    public func measure(_ canvas: BarCanvas) -> Double { Self.tagWidth * Double(manager.tagCount) }

    public func draw(_ canvas: BarCanvas, _ bounds: BarRect) {
        guard monitorIndex < manager.monitors.count else { return }
        let monitor = manager.monitors[monitorIndex]
        for i in 0..<manager.tagCount {
            let tagBounds = BarRect(x: bounds.x + Double(i) * Self.tagWidth, y: bounds.y, width: Self.tagWidth, height: bounds.height)
            let hasWindows = manager.hasWindowsOnTag(monitorIndex: monitorIndex, tagIndex: i)
            // While viewing all tags, highlight every occupied tag instead of a single "active" one.
            let isActive = monitor.isViewingAllTags ? hasWindows : i == monitor.activeTagIndex

            if isActive {
                canvas.fill(tagBounds, theme.activeTag)
            } else if hasWindows && useBackgroundIndicator {
                canvas.fill(tagBounds, theme.inactiveTagBackground)
            }

            let textColor = isActive ? theme.background : hasWindows ? theme.foreground : theme.emptyTagForeground
            canvas.drawText(String(i + 1), in: tagBounds, color: textColor, alignment: .center)

            if hasWindows && !useBackgroundIndicator {
                canvas.fill(BarRect(x: tagBounds.x + Self.markerInset, y: tagBounds.y + Self.markerInset,
                                    width: Self.markerSize, height: Self.markerSize), textColor)
            }
        }
    }

    public func onClick(_ xInSegment: Double) {
        let index = Int(xInSegment / Self.tagWidth)
        guard xInSegment >= 0, index < manager.tagCount else { return }
        manager.selectMonitor(monitorIndex)
        commands.tryExecute("view-tag", [String(index + 1)])
    }
}
