/// A window rectangle in screen points, in Accessibility (top-left origin, y grows downward)
/// coordinates of the global display space -- the same space AXPosition/AXSize use.
public struct LayoutRect: Equatable, Hashable, CustomStringConvertible {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// Degenerate: nothing can be laid out in it (e.g. a screen that just disappeared).
    public var isEmpty: Bool { width <= 0 || height <= 0 }

    public var description: String { "(\(x), \(y), \(width)x\(height))" }
}

/// Inputs to a layout's arrangement pass. Holds counts/params rather than windows so layouts
/// stay pure functions of geometry, unit-testable without any Accessibility state.
public struct LayoutContext {
    public var workArea: LayoutRect
    public var tiledWindowCount: Int
    public var params: [String: Double]

    public init(workArea: LayoutRect, tiledWindowCount: Int, params: [String: Double]) {
        self.workArea = workArea
        self.tiledWindowCount = tiledWindowCount
        self.params = params
    }
}

/// A pluggable tiling algorithm, registered by `name` and referenced from YAML config (e.g.
/// `layout: master-stack`). Implementations must be pure: same inputs, same outputs, no
/// Accessibility calls, no mutable state carried between calls. Mirrors Wtile's ILayout.
public protocol Layout {
    /// Registry key, referenced by name from YAML config.
    var name: String { get }

    /// Short glyph shown in the bar's layout segment (dwm-style, e.g. "[]=").
    var symbol: String { get }

    /// One rectangle per tiled window, in stack order (index 0 = master); exactly
    /// `context.tiledWindowCount` entries.
    func arrange(_ context: LayoutContext) -> [LayoutRect]
}

/// Helpers every layout shares (Wtile repeats these privately in each layout file).
enum LayoutMath {
    static func inset(_ rect: LayoutRect, gap: Int) -> LayoutRect {
        guard gap > 0 else { return rect }
        let half = gap / 2
        return LayoutRect(
            x: rect.x + half,
            y: rect.y + half,
            width: max(1, rect.width - gap),
            height: max(1, rect.height - gap))
    }

    static func param(_ params: [String: Double], _ key: String, _ fallback: Double) -> Double {
        guard let v = params[key], v.isFinite else { return fallback }
        return v
    }

    static func clamp<T: Comparable>(_ value: T, _ low: T, _ high: T) -> T {
        min(max(value, low), high)
    }

    /// Matches .NET's Math.Round default (banker's rounding), so Mtile and Wtile produce
    /// pixel-identical layouts for the same inputs.
    static func round(_ value: Double) -> Int {
        Int(value.rounded(.toNearestOrEven))
    }

    static func nmaster(_ params: [String: Double], count: Int) -> Int {
        clamp(Int(param(params, "nmaster", 1)), 0, count)
    }

    static func mfact(_ params: [String: Double]) -> Double {
        clamp(param(params, "mfact", 0.55), 0.05, 0.95)
    }

    static func gap(_ params: [String: Double]) -> Int {
        max(0, Int(param(params, "gap", 0)))
    }
}
