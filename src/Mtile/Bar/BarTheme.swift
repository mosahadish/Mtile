import Foundation

/// An sRGB color with 0-255 channels, kept AppKit-free so parsing is testable anywhere.
public struct RGBColor: Equatable {
    public var r: Int
    public var g: Int
    public var b: Int

    public init(_ r: Int, _ g: Int, _ b: Int) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// Accepts "#rrggbb" and "#rgb", like the hex forms of .NET's ColorTranslator.FromHtml.
    public static func parse(_ text: String) -> RGBColor? {
        var hex = text.trimmingCharacters(in: .whitespaces)
        guard hex.hasPrefix("#") else { return nil }
        hex.removeFirst()
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard hex.count == 6, let value = Int(hex, radix: 16) else { return nil }
        return RGBColor((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)
    }

    public static func blend(_ a: RGBColor, _ b: RGBColor, _ t: Double) -> RGBColor {
        RGBColor(Int(Double(a.r) + Double(b.r - a.r) * t),
                 Int(Double(a.g) + Double(b.g - a.g) * t),
                 Int(Double(a.b) + Double(b.b - a.b) * t))
    }
}

/// Color palette shared by every bar; rebuilt in place on config reload. Same derivations as
/// Wtile's BarTheme.
public final class BarTheme {
    public private(set) var background = RGBColor(0x1e, 0x1e, 0x2e)
    public private(set) var foreground = RGBColor(0xcd, 0xd6, 0xf4)
    public private(set) var activeTag = RGBColor(0x89, 0xb4, 0xfa)
    public private(set) var urgentTag = RGBColor(0xf3, 0x8b, 0xa8)
    public private(set) var inactiveTagBackground = RGBColor(0, 0, 0)
    public private(set) var emptyTagForeground = RGBColor(0, 0, 0)

    public init(_ config: BarColorsConfig) { apply(config) }

    public func apply(_ config: BarColorsConfig) {
        background = RGBColor.parse(config.background) ?? RGBColor(0x1e, 0x1e, 0x2e)
        foreground = RGBColor.parse(config.foreground) ?? RGBColor(0xcd, 0xd6, 0xf4)
        activeTag = RGBColor.parse(config.activeTag) ?? RGBColor(0x89, 0xb4, 0xfa)
        urgentTag = RGBColor.parse(config.urgentTag) ?? RGBColor(0xf3, 0x8b, 0xa8)
        inactiveTagBackground = RGBColor.parse(config.occupiedTag) ?? RGBColor.blend(background, foreground, 0.15)
        emptyTagForeground = RGBColor.blend(foreground, background, 0.5)
    }
}
