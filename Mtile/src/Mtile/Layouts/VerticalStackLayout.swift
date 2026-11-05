/// Every tiled window gets a full-width horizontal strip, stacked top to bottom. Only `gap`
/// applies. Registered as "vertical".
public struct VerticalStackLayout: Layout {
    public static let layoutName = "vertical"

    public init() {}

    public var name: String { Self.layoutName }
    public var symbol: String { "=" }

    public func arrange(_ context: LayoutContext) -> [LayoutRect] {
        let n = context.tiledWindowCount
        guard n > 0 else { return [] }

        let gap = LayoutMath.gap(context.params)
        let work = context.workArea
        var result: [LayoutRect] = []
        result.reserveCapacity(n)

        var y = work.y
        for i in 0..<n {
            let height = (work.height - (y - work.y)) / (n - i)
            result.append(LayoutMath.inset(LayoutRect(x: work.x, y: y, width: work.width, height: height), gap: gap))
            y += height
        }
        return result
    }
}
