/// A rectangle in bar-local points (origin top-left, y grows down).
public struct BarRect: Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Double { x + width }
}

public enum BarTextAlignment {
    case leading
    case center
}

/// The drawing surface a segment paints on. Wtile's segments draw on System.Drawing.Graphics;
/// Mtile puts a tiny protocol in between so segments and BarRenderer stay plain, testable Swift
/// and only BarWindow touches AppKit.
public protocol BarCanvas {
    func measure(_ text: String) -> Double
    func fill(_ rect: BarRect, _ color: RGBColor)
    /// Draws single-line text vertically centered in `rect`, truncated with an ellipsis if needed.
    func drawText(_ text: String, in rect: BarRect, color: RGBColor, alignment: BarTextAlignment)
}

/// One drawable, optionally-clickable piece of the bar (tags, layout symbol, title, clock).
/// Mirrors Wtile's ISegment.
public protocol Segment: AnyObject {
    /// Width in points this segment needs right now.
    func measure(_ canvas: BarCanvas) -> Double
    /// True for the one segment (the window title) that absorbs leftover bar width.
    var isFlexible: Bool { get }
    func draw(_ canvas: BarCanvas, _ bounds: BarRect)
    /// `xInSegment` is relative to the segment's left edge.
    func onClick(_ xInSegment: Double)
}

public extension Segment {
    var isFlexible: Bool { false }
    func onClick(_ xInSegment: Double) {}
}
