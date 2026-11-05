/// Where a dragged window lands in the stack: the tile nearest the cursor, before or after it.
public enum DropTarget {
    public static func distanceSquaredToRect(_ rect: LayoutRect, x: Int, y: Int) -> Int {
        let dx = max(max(rect.x - x, 0), x - (rect.x + rect.width - 1))
        let dy = max(max(rect.y - y, 0), y - (rect.y + rect.height - 1))
        return dx * dx + dy * dy
    }

    // The rect's diagonals split it into four triangles: right or bottom means after.
    public static func dropsAfterTile(_ rect: LayoutRect, x: Int, y: Int) -> Bool {
        let dx = (Double(x) - (Double(rect.x) + Double(rect.width) / 2)) / Double(max(rect.width, 1))
        let dy = (Double(y) - (Double(rect.y) + Double(rect.height) / 2)) / Double(max(rect.height, 1))
        return abs(dx) >= abs(dy) ? dx > 0 : dy > 0
    }
}
