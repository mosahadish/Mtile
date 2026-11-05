public final class LayoutSymbolSegment: Segment {
    private static let padding = 12.0

    private let manager: WindowManager
    private let theme: BarTheme
    private let monitorIndex: Int

    public init(manager: WindowManager, theme: BarTheme, monitorIndex: Int) {
        self.manager = manager
        self.theme = theme
        self.monitorIndex = monitorIndex
    }

    private var symbol: String { manager.layoutSymbol(monitorIndex: monitorIndex) }

    public func measure(_ canvas: BarCanvas) -> Double { canvas.measure(symbol) + Self.padding }

    public func draw(_ canvas: BarCanvas, _ bounds: BarRect) {
        canvas.drawText(symbol, in: bounds, color: theme.foreground, alignment: .center)
    }
}
