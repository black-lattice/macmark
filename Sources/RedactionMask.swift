import AppKit

extension Annotation {
    var redactionPath: NSBezierPath {
        guard isBrushRedaction else { return NSBezierPath(rect: bounds) }
        guard let first = points.first else { return NSBezierPath() }
        if points.count == 1 {
            return NSBezierPath(ovalIn: CGRect(x: first.x - brushSize / 2, y: first.y - brushSize / 2,
                                              width: brushSize, height: brushSize))
        }
        let centerline = CGMutablePath()
        centerline.move(to: first)
        for point in points.dropFirst() { centerline.addLine(to: point) }
        return NSBezierPath(cgPath: centerline.copy(strokingWithWidth: brushSize, lineCap: .round, lineJoin: .round, miterLimit: 10))
    }
    func selectionPath(scale: CGFloat) -> NSBezierPath {
        if tool.isRedaction { return redactionPath }
        return NSBezierPath(rect: tool == .rectangle ? bounds : bounds.insetBy(dx: -5 / scale, dy: -5 / scale))
    }
}
