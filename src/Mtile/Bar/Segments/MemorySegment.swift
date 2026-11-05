public final class MemorySegment: Segment {
    private static let padding = 12.0
    static let defaultFormat = "MEM {0}%"
    private static let maxPercent = 100

    private let theme: BarTheme
    private let format: String?
    private let percent: () -> Double

    public init(theme: BarTheme, format: String?, percent: @escaping () -> Double = SystemStats.memoryPercent) {
        self.theme = theme
        self.format = format
        self.percent = percent
    }

    static func text(_ format: String?, _ percent: Int) -> String {
        SegmentFormat.apply(format ?? defaultFormat, fallback: defaultFormat, [String(percent)])
    }

    // See CpuSegment: reserves width for 100% so the bar doesn't shift as the digit count changes.
    public func measure(_ canvas: BarCanvas) -> Double { canvas.measure(Self.text(format, Self.maxPercent)) + Self.padding }

    public func draw(_ canvas: BarCanvas, _ bounds: BarRect) {
        canvas.drawText(Self.text(format, Int(percent())), in: bounds, color: theme.foreground, alignment: .center)
    }
}
