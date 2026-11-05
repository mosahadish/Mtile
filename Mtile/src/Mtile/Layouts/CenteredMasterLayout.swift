/// dwm's centeredmaster: the master column is horizontally centered (width = `mfact` *
/// work-area width), stack windows alternate into columns flanking it (right, left, right, ...).
/// A single window gets a centered, mfact-wide, full-height box instead of going fullscreen.
public struct CenteredMasterLayout: Layout {
    public static let layoutName = "centered-master"

    public init() {}

    public var name: String { Self.layoutName }
    public var symbol: String { "|M|" }

    public func arrange(_ context: LayoutContext) -> [LayoutRect] {
        let n = context.tiledWindowCount
        guard n > 0 else { return [] }

        let nmaster = LayoutMath.nmaster(context.params, count: n)
        let mfact = LayoutMath.mfact(context.params)
        let gap = LayoutMath.gap(context.params)
        let work = context.workArea
        var result = Array(repeating: LayoutRect(x: 0, y: 0, width: 0, height: 0), count: n)

        if n == 1 {
            let w = LayoutMath.round(Double(work.width) * mfact)
            let x = work.x + (work.width - w) / 2
            result[0] = LayoutMath.inset(LayoutRect(x: x, y: work.y, width: w, height: work.height), gap: gap)
            return result
        }

        let masterCount = min(n, nmaster)
        let stackCount = n - masterCount

        if stackCount == 0 {
            stack(&result, indices: Array(0..<masterCount), x: work.x, width: work.width, work: work, gap: gap)
            return result
        }

        let masterWidth = masterCount > 0 ? LayoutMath.round(Double(work.width) * mfact) : 0
        let sideWidth = (work.width - masterWidth) / 2
        let masterX = work.x + sideWidth
        let leftX = work.x
        let rightX = masterX + masterWidth

        stack(&result, indices: Array(0..<masterCount), x: masterX, width: masterWidth, work: work, gap: gap)

        var rightIndices: [Int] = []
        var leftIndices: [Int] = []
        for i in masterCount..<n {
            if (i - masterCount) % 2 == 0 {
                rightIndices.append(i)
            } else {
                leftIndices.append(i)
            }
        }

        stack(&result, indices: rightIndices, x: rightX, width: sideWidth, work: work, gap: gap)
        stack(&result, indices: leftIndices, x: leftX, width: sideWidth, work: work, gap: gap)
        return result
    }

    private func stack(_ result: inout [LayoutRect], indices: [Int], x: Int, width: Int, work: LayoutRect, gap: Int) {
        var y = work.y
        for (k, index) in indices.enumerated() {
            let h = (work.height - (y - work.y)) / (indices.count - k)
            result[index] = LayoutMath.inset(LayoutRect(x: x, y: y, width: width, height: h), gap: gap)
            y += h
        }
    }
}
