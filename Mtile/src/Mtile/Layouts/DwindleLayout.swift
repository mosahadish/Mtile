/// dwm's fibonacci "dwindle": window 0 takes an `mfact`-wide left column, then each remaining
/// rectangle is halved for the next window, alternating vertical/horizontal cuts; the last window
/// gets whatever is left. `nmaster` is not used.
public struct DwindleLayout: Layout {
    public static let layoutName = "dwindle"

    public init() {}

    public var name: String { Self.layoutName }
    public var symbol: String { "[\\]" }

    public func arrange(_ context: LayoutContext) -> [LayoutRect] {
        let n = context.tiledWindowCount
        guard n > 0 else { return [] }

        let mfact = LayoutMath.mfact(context.params)
        let gap = LayoutMath.gap(context.params)
        var remaining = context.workArea

        if n == 1 {
            return [LayoutMath.inset(remaining, gap: gap)]
        }

        var result: [LayoutRect] = []
        result.reserveCapacity(n)

        for i in 0..<(n - 1) {
            let fraction = i == 0 ? mfact : 0.5
            if i % 2 == 0 {
                let width = LayoutMath.round(Double(remaining.width) * fraction)
                result.append(LayoutMath.inset(LayoutRect(x: remaining.x, y: remaining.y, width: width, height: remaining.height), gap: gap))
                remaining = LayoutRect(x: remaining.x + width, y: remaining.y, width: remaining.width - width, height: remaining.height)
            } else {
                let height = LayoutMath.round(Double(remaining.height) * fraction)
                result.append(LayoutMath.inset(LayoutRect(x: remaining.x, y: remaining.y, width: remaining.width, height: height), gap: gap))
                remaining = LayoutRect(x: remaining.x, y: remaining.y + height, width: remaining.width, height: remaining.height - height)
            }
        }

        result.append(LayoutMath.inset(remaining, gap: gap))
        return result
    }
}
