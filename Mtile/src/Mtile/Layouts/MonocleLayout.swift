/// dwm's monocle: every tiled window gets the full work area; only the focused one is visible.
public struct MonocleLayout: Layout {
    public static let layoutName = "monocle"

    public init() {}

    public var name: String { Self.layoutName }
    public var symbol: String { "[M]" }

    public func arrange(_ context: LayoutContext) -> [LayoutRect] {
        Array(repeating: context.workArea, count: max(0, context.tiledWindowCount))
    }
}
