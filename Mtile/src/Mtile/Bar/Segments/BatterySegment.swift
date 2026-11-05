/// Renders nothing (zero width, no draw) when the Mac has no internal battery -- a desktop
/// shouldn't show a garbage "BAT 0%". Same as Wtile's BatterySegment.
public final class BatterySegment: Segment {
    private static let padding = 12.0
    static let defaultFormat = "BAT {0}% {1}"
    private static let maxPercent = 100
    private static let widestStateWord = "Charging" // longest of "", "AC", "Charging"

    private let theme: BarTheme
    private let format: String?
    private let battery: () -> BatteryStatus

    public init(theme: BarTheme, format: String?, battery: @escaping () -> BatteryStatus = SystemStats.battery) {
        self.theme = theme
        self.format = format
        self.battery = battery
    }

    static func stateWord(_ battery: BatteryStatus) -> String {
        battery.isCharging ? "Charging" : battery.isOnAc ? "AC" : ""
    }

    static func text(_ format: String?, _ percent: Int, _ stateWord: String) -> String {
        let text = SegmentFormat.apply(format ?? defaultFormat, fallback: defaultFormat, [String(percent), stateWord])
        // .NET TrimEnd(): drops the trailing space left by an empty state word.
        return String(text.reversed().drop(while: \.isWhitespace).reversed())
    }

    // Reserves width for the widest percent/state combination rather than the live one, so the
    // segment doesn't shift the rest of the bar as the percent or charging state changes.
    public func measure(_ canvas: BarCanvas) -> Double {
        guard battery().hasBattery else { return 0 }
        return canvas.measure(Self.text(format, Self.maxPercent, Self.widestStateWord)) + Self.padding
    }

    public func draw(_ canvas: BarCanvas, _ bounds: BarRect) {
        let status = battery()
        guard status.hasBattery else { return }
        canvas.drawText(Self.text(format, status.percent, Self.stateWord(status)), in: bounds, color: theme.foreground, alignment: .center)
    }
}
