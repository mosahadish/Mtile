import Foundation

public final class ClockSegment: Segment {
    private static let padding = 12.0

    /// Same output as Wtile's "ddd dd-MMM-yyyy HH:mm:ss" (e.g. "Thu 10-Sep-2026 02:35:11");
    /// .NET's "ddd" is "EEE" in Unicode date patterns.
    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE dd-MMM-yyyy HH:mm:ss"
        return f
    }()

    private let theme: BarTheme
    private let now: () -> Date

    public init(theme: BarTheme, now: @escaping () -> Date = Date.init) {
        self.theme = theme
        self.now = now
    }

    var text: String { Self.formatter.string(from: now()) }

    public func measure(_ canvas: BarCanvas) -> Double { canvas.measure(text) + Self.padding }

    public func draw(_ canvas: BarCanvas, _ bounds: BarRect) {
        canvas.drawText(text, in: bounds, color: theme.foreground, alignment: .center)
    }
}
