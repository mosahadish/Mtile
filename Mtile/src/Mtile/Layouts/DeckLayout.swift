/// dwm's deck: masters tile side by side like master-stack, but every stack window gets the
/// full stack-area rectangle (monocle-style overlap confined to the stack region).
public struct DeckLayout: Layout {
    public static let layoutName = "deck"

    public init() {}

    public var name: String { Self.layoutName }
    public var symbol: String { "[D]" }

    public func arrange(_ context: LayoutContext) -> [LayoutRect] {
        let n = context.tiledWindowCount
        guard n > 0 else { return [] }

        let nmaster = LayoutMath.nmaster(context.params, count: n)
        let mfact = LayoutMath.mfact(context.params)
        let gap = LayoutMath.gap(context.params)
        let work = context.workArea

        let masterCount = min(n, nmaster)
        let hasStack = n > masterCount
        let masterWidth = masterCount > 0
            ? (hasStack ? LayoutMath.round(Double(work.width) * mfact) : work.width)
            : 0
        let stackWidth = work.width - masterWidth
        let stackX = work.x + masterWidth

        var result: [LayoutRect] = []
        result.reserveCapacity(n)

        var colX = work.x
        for i in 0..<masterCount {
            let width = (masterWidth - (colX - work.x)) / (masterCount - i)
            result.append(LayoutMath.inset(LayoutRect(x: colX, y: work.y, width: width, height: work.height), gap: gap))
            colX += width
        }

        if hasStack {
            let stackRect = LayoutMath.inset(LayoutRect(x: stackX, y: work.y, width: stackWidth, height: work.height), gap: gap)
            result.append(contentsOf: Array(repeating: stackRect, count: n - masterCount))
        }
        return result
    }
}
