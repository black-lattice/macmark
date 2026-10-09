import AppKit

// A shared 20-point grid and rounded strokes keep all capture actions visually consistent.
enum CaptureToolbarIcon {
    case rectangle, line, arrow, pen, text, blur, mosaic, select, undo, redo, cancel, pin, save, copy
    static func forTool(_ tool: MarkTool) -> CaptureToolbarIcon {
        switch tool {
        case .rectangle: return .rectangle
        case .line: return .line
        case .arrow: return .arrow
        case .pen: return .pen
        case .text: return .text
        case .select: return .select
        case .blur: return .blur
        case .mosaic: return .mosaic
        }
    }
    func image(color: NSColor) -> NSImage {
        NSImage(size: CGSize(width: 20, height: 20), flipped: false) { _ in
            var path = NSBezierPath()
            func points(_ coordinates: [(CGFloat, CGFloat)]) {
                guard let first = coordinates.first else { return }
                path.move(to: CGPoint(x: first.0, y: first.1))
                for point in coordinates.dropFirst() { path.line(to: CGPoint(x: point.0, y: point.1)) }
            }
            switch self {
            case .rectangle:
                path = NSBezierPath(roundedRect: CGRect(x: 3, y: 4, width: 14, height: 12), xRadius: 2, yRadius: 2)
            case .line:
                points([(4, 4), (16, 16)])
            case .arrow:
                points([(4, 4), (16, 16)])
                points([(8, 16), (16, 16), (16, 8)])
            case .pen:
                points([(3, 3), (4, 8), (14, 18), (18, 14), (8, 4), (3, 3)])
                points([(12, 16), (16, 12)])
                points([(4, 8), (8, 4)])
            case .text:
                points([(4, 16), (16, 16)])
                points([(10, 16), (10, 4)])
                points([(7, 4), (13, 4)])
            case .select:
                points([(4, 17), (4, 3), (8, 7), (12, 2), (15, 4), (11, 9), (17, 9), (4, 17)])
            case .blur:
                path.appendOval(in: CGRect(x: 3, y: 3, width: 14, height: 14))
                for y in [CGFloat(6), 10, 14] {
                    points([(7, y), (13, y)])
                }
            case .mosaic:
                for x in [CGFloat(3), 8, 13] {
                    for y in [CGFloat(3), 8, 13] { path.appendRect(CGRect(x: x, y: y, width: 3, height: 3)) }
                }
            case .undo:
                path.move(to: CGPoint(x: 16, y: 4))
                path.curve(to: CGPoint(x: 5, y: 14), controlPoint1: CGPoint(x: 19, y: 13), controlPoint2: CGPoint(x: 12, y: 16))
                points([(8, 18), (4, 14), (8, 10)])
            case .redo:
                path.move(to: CGPoint(x: 4, y: 4))
                path.curve(to: CGPoint(x: 15, y: 14), controlPoint1: CGPoint(x: 1, y: 13), controlPoint2: CGPoint(x: 8, y: 16))
                points([(12, 18), (16, 14), (12, 10)])
            case .cancel:
                points([(5, 5), (15, 15)]); points([(5, 15), (15, 5)])
            case .pin:
                points([(8, 17), (16, 9), (14, 7), (12, 9), (8, 7), (7, 8), (9, 12), (7, 14), (8, 17)])
                points([(8, 8), (3, 3)])
            case .save:
                points([(10, 17), (10, 7)]); points([(6, 11), (10, 7), (14, 11)])
                points([(3, 7), (3, 3), (17, 3), (17, 7)])
            case .copy:
                points([(4, 9), (8, 5), (16, 15)])
            }
            color.setStroke()
            path.lineWidth = 1.7; path.lineCapStyle = .round; path.lineJoinStyle = .round
            path.stroke()
            return true
        }
    }
}
