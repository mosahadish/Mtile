/// Renders nothing when there's no default output device with a readable volume, same rule as
/// BatterySegment with no battery. Same as Wtile's VolumeSegment.
public final class VolumeSegment: Segment {
    private static let padding = 12.0
    static let defaultFormat = "VOL {0}%"
    static let mutedText = "MUTED" // shown bare, ignoring the format string's own prefix/suffix

    private let theme: BarTheme
    private let format: String?
    private let volume: () -> VolumeStatus?

    public init(theme: BarTheme, format: String?, volume: @escaping () -> VolumeStatus? = VolumeStats.volume) {
        self.theme = theme
        self.format = format
        self.volume = volume
    }

    static func text(_ format: String?, _ percent: Int) -> String {
        SegmentFormat.apply(format ?? defaultFormat, fallback: defaultFormat, [String(percent)])
    }

    // Reserves width for whichever of "VOL 100%"/"MUTED" is wider, so toggling mute or the
    // percent's digit count doesn't shift the rest of the bar.
    public func measure(_ canvas: BarCanvas) -> Double {
        guard volume() != nil else { return 0 }
        return max(canvas.measure(Self.text(format, 100)), canvas.measure(Self.mutedText)) + Self.padding
    }

    public func draw(_ canvas: BarCanvas, _ bounds: BarRect) {
        guard let status = volume() else { return }
        let text = status.muted ? Self.mutedText : Self.text(format, status.percent)
        canvas.drawText(text, in: bounds, color: theme.foreground, alignment: .center)
    }
}
