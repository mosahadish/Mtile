/// Shows the focused window's title. Absorbs whatever space is left in the bar.
public final class TitleSegment: Segment {
    private static let padding = 8.0

    private let manager: WindowManager
    private let theme: BarTheme

    public init(manager: WindowManager, theme: BarTheme) {
        self.manager = manager
        self.theme = theme
    }

    public var isFlexible: Bool { true }

    public func measure(_ canvas: BarCanvas) -> Double { 0 } // flexible: BarRenderer decides the width

    public func draw(_ canvas: BarCanvas, _ bounds: BarRect) {
        guard bounds.width > 0 else { return }
        let textBounds = BarRect(x: bounds.x + Self.padding, y: bounds.y, width: max(0, bounds.width - Self.padding), height: bounds.height)
        // bug.n-style: a "~" prefix marks the focused window as floating.
        let text = manager.isFocusedFloating ? "~ \(manager.focusedTitle)" : manager.focusedTitle
        canvas.drawText(text, in: textBounds, color: theme.foreground, alignment: .leading)
    }
}
