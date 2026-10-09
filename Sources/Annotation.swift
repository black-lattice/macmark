import AppKit

enum MarkTool: String, CaseIterable {
    case select, arrow, line, pen, rectangle, text
    var title: String {
        switch self {
        case .select: return "选择"
        case .arrow: return "箭头"
        case .line: return "直线"
        case .pen: return "画笔"
        case .rectangle: return "方框"
        case .text: return "文字"
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
    init(tool: MarkTool, points: [CGPoint], color: NSColor, width: CGFloat, text: String = "") {
        id = UUID()
        self.tool = tool
        self.points = points
        self.color = color
        self.width = width
        self.text = text
    }
    var bounds: CGRect {
        guard let first = points.first else { return .zero }
        if tool == .text {
            let size = (text as NSString).size(withAttributes: textAttributes)
            return CGRect(origin: first, size: size)
        }
        return points.reduce(CGRect(origin: first, size: .zero)) { rect, point in
            CGRect(x: min(rect.minX, point.x), y: min(rect.minY, point.y),
                   width: max(rect.maxX, point.x) - min(rect.minX, point.x),
                   height: max(rect.maxY, point.y) - min(rect.minY, point.y))
        }
    }
    var textAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: max(16, width * 6), weight: .semibold), .foregroundColor: color]
    }
    func contains(_ point: CGPoint) -> Bool {
        let tolerance = max(6, width * 2)
        if tool == .text { return bounds.insetBy(dx: -4, dy: -4).contains(point) }
        guard let first = points.first, let last = points.last else { return false }
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
