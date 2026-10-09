import AppKit

enum AnnotationCursor {
    static let brush = NSCursor(image: NSImage(size: CGSize(width: 1, height: 1), flipped: false) { _ in true }, hotSpot: .zero)
    private static let risingDiagonal = diagonal(rising: true)
    private static let fallingDiagonal = diagonal(rising: false)
    static func resize(corner: Int) -> NSCursor {
        corner % 2 == 0 ? fallingDiagonal : risingDiagonal
    }
    static func resize(mark: Annotation, handle: Int) -> NSCursor {
        let points = mark.editingHandles
        guard points.indices.contains(handle) else { return .crosshair }
        let opposite = points[mark.tool.isRegion ? (handle + 2) % 4 : 1 - handle]
        let dx = points[handle].x - opposite.x, dy = points[handle].y - opposite.y
        if abs(dy) <= abs(dx) * 0.4 { return .resizeLeftRight }
        if abs(dx) <= abs(dy) * 0.4 { return .resizeUpDown }
        return dx * dy < 0 ? risingDiagonal : fallingDiagonal
    }
    private static func diagonal(rising: Bool) -> NSCursor {
        let image = NSImage(size: CGSize(width: 24, height: 24), flipped: false) { _ in
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: rising ? y : 24 - y) }
            let path = NSBezierPath()
            path.move(to: point(5, 5)); path.line(to: point(19, 19))
            path.move(to: point(11, 5)); path.line(to: point(5, 5)); path.line(to: point(5, 11))
            path.move(to: point(13, 19)); path.line(to: point(19, 19)); path.line(to: point(19, 13))
            path.lineCapStyle = .round; path.lineJoinStyle = .round
            NSColor.white.setStroke(); path.lineWidth = 4; path.stroke()
            NSColor.black.setStroke(); path.lineWidth = 2; path.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: CGPoint(x: 12, y: 12))
    }
}
