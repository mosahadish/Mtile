public final class NetworkSegment: Segment {
    private static let padding = 12.0
    static let defaultFormat = "↓{0} ↑{1}"
    // Widest rate reserved for: covers up to ~1GB/s. Faster sustained rates still jitter the width,
    // which isn't worth wasting bar space on for every normal reading. Same as Wtile.
    private static let widestRate = "999.9MB/s"

    private let theme: BarTheme
    private let format: String?
    private let rate: () -> NetworkRate

    public init(theme: BarTheme, format: String?, rate: @escaping () -> NetworkRate = SystemStats.networkRate) {
        self.theme = theme
        self.format = format
        self.rate = rate
    }

    static func text(_ format: String?, _ down: String, _ up: String) -> String {
        SegmentFormat.apply(format ?? defaultFormat, fallback: defaultFormat, [down, up])
    }

    public func measure(_ canvas: BarCanvas) -> Double {
        canvas.measure(Self.text(format, Self.widestRate, Self.widestRate)) + Self.padding
    }

    public func draw(_ canvas: BarCanvas, _ bounds: BarRect) {
        let r = rate()
        let text = Self.text(format, ByteRateFormatter.format(r.downBytesPerSec), ByteRateFormatter.format(r.upBytesPerSec))
        canvas.drawText(text, in: bounds, color: theme.foreground, alignment: .center)
    }
}
