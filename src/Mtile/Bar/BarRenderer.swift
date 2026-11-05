public struct SegmentHit {
    public let segment: Segment
    public let bounds: BarRect
}

/// Pure layout+paint logic for one bar: measures fixed-width segments, gives whatever's left to
/// the one flexible segment (the title), draws left-to-right / right-to-left, and returns the
/// hit-test rectangles BarWindow uses to dispatch clicks. Same algorithm as Wtile's BarRenderer.
public final class BarRenderer {
    private let left: [Segment]
    private let right: [Segment]
    private let theme: BarTheme

    public init(left: [Segment], right: [Segment], theme: BarTheme) {
        self.left = left
        self.right = right
        self.theme = theme
    }

    /// `obstruction` is a bar-local horizontal range nothing may be drawn under (the MacBook
    /// notch): left segments and the flexible title stop at its left edge.
    public func draw(_ canvas: BarCanvas, _ clientBounds: BarRect, obstruction: ClosedRange<Double>? = nil) -> [SegmentHit] {
        var hits: [SegmentHit] = []
        canvas.fill(clientBounds, theme.background)

        var leftWidths = [Double](repeating: 0, count: left.count)
        var leftFixedTotal = 0.0
        var flexIndex: Int?
        for (i, segment) in left.enumerated() {
            if segment.isFlexible {
                flexIndex = i
                continue
            }
            leftWidths[i] = segment.measure(canvas)
            leftFixedTotal += leftWidths[i]
        }

        let rightWidths = right.map { $0.measure(canvas) }
        let rightTotal = rightWidths.reduce(0, +)

        if let flexIndex {
            var flexEnd = clientBounds.maxX - rightTotal
            if let obstruction, obstruction.lowerBound > clientBounds.x + leftFixedTotal {
                flexEnd = min(flexEnd, obstruction.lowerBound)
            }
            leftWidths[flexIndex] = max(0, flexEnd - clientBounds.x - leftFixedTotal)
        }

        var x = clientBounds.x
        for (i, segment) in left.enumerated() {
            let bounds = BarRect(x: x, y: clientBounds.y, width: leftWidths[i], height: clientBounds.height)
            segment.draw(canvas, bounds)
            hits.append(SegmentHit(segment: segment, bounds: bounds))
            x += leftWidths[i]
        }

        var rx = clientBounds.maxX - rightTotal
        for (i, segment) in right.enumerated() {
            let bounds = BarRect(x: rx, y: clientBounds.y, width: rightWidths[i], height: clientBounds.height)
            segment.draw(canvas, bounds)
            hits.append(SegmentHit(segment: segment, bounds: bounds))
            rx += rightWidths[i]
        }

        return hits
    }

    /// Dispatches a click at bar-local `x` to the segment under it.
    public static func click(_ hits: [SegmentHit], x: Double) {
        if let hit = hits.first(where: { x >= $0.bounds.x && x < $0.bounds.maxX }) {
            hit.segment.onClick(x - hit.bounds.x)
        }
    }
}
