public final class CpuSegment: Segment {
    private static let padding = 12.0
    static let defaultFormat = "CPU {0}%"
    private static let maxPercent = 100 // widest value this can render

    private let theme: BarTheme
    private let format: String?
    private let percent: () -> Double

    public init(theme: BarTheme, format: String?, percent: @escaping () -> Double = SystemStats.cpuPercent) {
        self.theme = theme
        self.format = format
        self.percent = percent
    }

    static func text(_ format: String?, _ percent: Int) -> String {
        SegmentFormat.apply(format ?? defaultFormat, fallback: defaultFormat, [String(percent)])
    }

    // Reserves width for the widest possible value (100%) instead of the live one, so the segment
    // -- and everything laid out after it -- doesn't shift as the digit count changes.
    public func measure(_ canvas: BarCanvas) -> Double { canvas.measure(Self.text(format, Self.maxPercent)) + Self.padding }

    public func draw(_ canvas: BarCanvas, _ bounds: BarRect) {
        canvas.drawText(Self.text(format, Int(percent().rounded())), in: bounds, color: theme.foreground, alignment: .center)
    }
}
