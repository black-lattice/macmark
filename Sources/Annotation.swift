import AppKit

enum RedactionMode: Int {
    case region, brush
}

enum MarkTool: String, CaseIterable {
    case select, arrow, line, pen, rectangle, text, blur, mosaic
    var isRedaction: Bool { self == .blur || self == .mosaic }
    var isRegion: Bool { self == .rectangle || isRedaction }
    var title: String {
        switch self {
        case .select: return "选择"
        case .arrow: return "箭头"
        case .line: return "直线"
        case .pen: return "画笔"
        case .rectangle: return "方框"
        case .text: return "文字"
        case .blur: return "高斯模糊"
        case .mosaic: return "马赛克"
        }
    }
    var key: String {
        switch self {
        case .select: return "v"
        case .arrow: return "a"
        case .line: return "l"
        case .pen: return "p"
        case .rectangle: return "r"
        case .text: return "t"
        case .blur: return "b"
        case .mosaic: return "m"
        }
    }
    var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .pen: return "pencil.tip"
        case .rectangle: return "rectangle"
        case .text: return "textformat"
        case .blur: return "drop.halffull"
        case .mosaic: return "square.grid.3x3.fill"
        }
    }
}

struct Annotation {
    let id: UUID
    let tool: MarkTool
    var points: [CGPoint]
    var color: NSColor
    var width: CGFloat
    var text: String
    var fontSize: CGFloat?
    let redactionMode: RedactionMode
    let brushSize: CGFloat
    var isBrushRedaction: Bool { tool.isRedaction && redactionMode == .brush }
    init(tool: MarkTool, points: [CGPoint], color: NSColor, width: CGFloat, text: String = "",
         redactionMode: RedactionMode = .region, brushSize: CGFloat = 24, fontSize: CGFloat? = nil) {
        id = UUID()
        self.tool = tool
        self.points = points
        self.color = color
        self.width = width
        self.text = text
        self.redactionMode = redactionMode
        self.brushSize = brushSize
        self.fontSize = fontSize
    }
    var bounds: CGRect {
        guard let first = points.first else { return .zero }
        if tool == .text {
            let size = (text as NSString).size(withAttributes: textAttributes)
            return CGRect(origin: first, size: size)
        }
        if tool == .arrow { return arrowPath.bounds }
        if isBrushRedaction { return redactionPath.bounds }
        return points.reduce(CGRect(origin: first, size: .zero)) { rect, point in
            CGRect(x: min(rect.minX, point.x), y: min(rect.minY, point.y),
                   width: max(rect.maxX, point.x) - min(rect.minX, point.x),
                   height: max(rect.maxY, point.y) - min(rect.minY, point.y))
        }
    }
    var textAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: fontSize ?? max(16, width * 6), weight: .semibold), .foregroundColor: color]
    }
    var arrowPath: NSBezierPath {
        let path = NSBezierPath()
        guard let first = points.first, let last = points.last else { return path }
        let dx = last.x - first.x, dy = last.y - first.y
        let length = hypot(dx, dy)
        guard length > 0 else { return path }
        let ux = dx / length, uy = dy / length
        let headLength = min(length * 0.35, max(14, width * 6 + length * 0.04))
        let thickness = sqrt(max(0.5, width) / 3)
        func offset(back: CGFloat, side: CGFloat) -> CGPoint {
            CGPoint(x: last.x - ux * back - uy * side, y: last.y - uy * back + ux * side)
        }
        path.move(to: first)
        path.line(to: offset(back: headLength * 0.9, side: headLength * 0.34 * thickness))
        path.line(to: offset(back: headLength, side: headLength * 0.6 * thickness))
        path.line(to: last)
        path.line(to: offset(back: headLength, side: -headLength * 0.6 * thickness))
        path.line(to: offset(back: headLength * 0.9, side: -headLength * 0.34 * thickness))
        path.close()
        return path
    }
    var editingHandles: [CGPoint] {
        guard points.count >= 2, !isBrushRedaction else { return [] }
        if tool == .arrow || tool == .line { return [points[0], points[1]] }
        if tool.isRegion {
            let b = bounds
            return [CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.maxX, y: b.minY),
                    CGPoint(x: b.maxX, y: b.maxY), CGPoint(x: b.minX, y: b.maxY)]
        }
        return []
    }
    func handle(at point: CGPoint, tolerance: CGFloat) -> Int? {
        editingHandles.indices.min(by: {
            hypot(editingHandles[$0].x - point.x, editingHandles[$0].y - point.y)
                < hypot(editingHandles[$1].x - point.x, editingHandles[$1].y - point.y)
        }).flatMap { index in
            hypot(editingHandles[index].x - point.x, editingHandles[index].y - point.y) <= tolerance ? index : nil
        }
    }
    mutating func resize(handle index: Int, to point: CGPoint, from original: Annotation, constrained: Bool) {
        guard original.editingHandles.indices.contains(index) else { return }
        let anchor = original.editingHandles[tool.isRegion ? (index + 2) % 4 : 1 - index]
        var end = point
        if constrained {
            if tool.isRegion {
                let length = max(abs(point.x - anchor.x), abs(point.y - anchor.y))
                end = CGPoint(x: anchor.x + (point.x >= anchor.x ? length : -length),
                              y: anchor.y + (point.y >= anchor.y ? length : -length))
            } else { end = Geometry.constrained(point, from: anchor) }
        }
        if tool.isRegion { points = [anchor, end] }
        else { points[index] = end }
    }
    func contains(_ point: CGPoint) -> Bool {
        let tolerance = max(6, width * 2)
        if isBrushRedaction { return redactionPath.contains(point) }
        if tool == .text { return bounds.insetBy(dx: -4, dy: -4).contains(point) }
        guard let first = points.first, let last = points.last else { return false }
        if tool.isRedaction { return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point) }
        if tool == .arrow && arrowPath.contains(point) { return true }
        if tool == .rectangle {
            let b = bounds
            return b.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
                && !b.insetBy(dx: tolerance, dy: tolerance).contains(point)
        }
        let segments = tool == .pen ? points : [first, last]
        return zip(segments, segments.dropFirst()).contains { a, b in
            let dx = b.x - a.x, dy = b.y - a.y
            let length = dx * dx + dy * dy
            let t = length == 0 ? 0 : max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / length))
            return hypot(point.x - a.x - t * dx, point.y - a.y - t * dy) <= tolerance
        }
    }
    mutating func move(by offset: CGPoint) {
        points = points.map { CGPoint(x: $0.x + offset.x, y: $0.y + offset.y) }
    }
}

enum Geometry {
    static func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }
    static func constrained(_ end: CGPoint, from start: CGPoint) -> CGPoint {
        let distance = hypot(end.x - start.x, end.y - start.y)
        let angle = (atan2(end.y - start.y, end.x - start.x) / (.pi / 4)).rounded() * (.pi / 4)
        return CGPoint(x: start.x + cos(angle) * distance, y: start.y + sin(angle) * distance)
    }
    // Overlay and editor use top-left coordinates; CGImage cropping uses pixel coordinates.
    static func cropRect(selection: CGRect, screenSize: CGSize, imageSize: CGSize) -> CGRect {
        let clipped = selection.intersection(CGRect(origin: .zero, size: screenSize))
        guard !clipped.isNull, screenSize.width > 0, screenSize.height > 0 else { return .zero }
        return CGRect(x: clipped.minX * imageSize.width / screenSize.width,
                      y: clipped.minY * imageSize.height / screenSize.height,
                      width: clipped.width * imageSize.width / screenSize.width,
                      height: clipped.height * imageSize.height / screenSize.height).integral
            .intersection(CGRect(origin: .zero, size: imageSize))
    }
}
