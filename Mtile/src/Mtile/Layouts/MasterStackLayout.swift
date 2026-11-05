/// Master-stack tiling: the first `nmaster` windows occupy a resizable master area (width =
/// `mfact` * work-area width) as side-by-side columns (bug.n-style); the rest stack vertically in
/// the stack area. `masterOnRight` mirrors which side the master area sits on (dwm's rmaster):
/// "master-stack" ("[]=") or "master-stack-right" ("=[]").
public struct MasterStackLayout: Layout {
    public static let layoutName = "master-stack"
    public static let rightLayoutName = "master-stack-right"

    public let masterOnRight: Bool

    public init(masterOnRight: Bool = false) {
        self.masterOnRight = masterOnRight
    }

    public var name: String { masterOnRight ? Self.rightLayoutName : Self.layoutName }
    public var symbol: String { masterOnRight ? "=[]" : "[]=" }

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

        let masterX = masterOnRight ? work.x + stackWidth : work.x
        let stackX = masterOnRight ? work.x : work.x + masterWidth

        var result: [LayoutRect] = []
        result.reserveCapacity(n)

        var colX = masterX
        for i in 0..<masterCount {
            let width = (masterWidth - (colX - masterX)) / (masterCount - i)
            result.append(LayoutMath.inset(LayoutRect(x: colX, y: work.y, width: width, height: work.height), gap: gap))
            colX += width
        }

        var stackY = work.y
        for i in masterCount..<n {
            let height = (work.height - (stackY - work.y)) / (n - i)
            result.append(LayoutMath.inset(LayoutRect(x: stackX, y: stackY, width: stackWidth, height: height), gap: gap))
            stackY += height
        }

        return result
    }
}
