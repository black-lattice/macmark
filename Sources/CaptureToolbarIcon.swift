import AppKit

// A shared 20-point grid and rounded strokes keep all capture actions visually consistent.
enum CaptureToolbarIcon {
    case rectangle, line, arrow, pen, text, select, settings, undo, redo, cancel, save, copy
    static func forTool(_ tool: MarkTool) -> CaptureToolbarIcon {
        switch tool {
        case .rectangle: return .rectangle
        case .line: return .line
        case .arrow: return .arrow
        case .pen: return .pen
        case .text: return .text
        case .select: return .select
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
            case .settings:
                for y in [CGFloat(5), 10, 15] { points([(3, y), (17, y)]) }
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
            case .save:
                points([(10, 17), (10, 7)]); points([(6, 11), (10, 7), (14, 11)])
                points([(3, 7), (3, 3), (17, 3), (17, 7)])
            case .copy:
                points([(4, 9), (8, 5), (16, 15)])
            }
            color.setStroke()
            path.lineWidth = 1.7; path.lineCapStyle = .round; path.lineJoinStyle = .round
            path.stroke()
            if case .settings = self {
                for (x, y) in [(CGFloat(7), CGFloat(15)), (13, 10), (8, 5)] {
                    let knob = NSBezierPath(ovalIn: CGRect(x: x - 2, y: y - 2, width: 4, height: 4))
                    NSColor.white.setFill(); knob.fill()
                    color.setStroke(); knob.lineWidth = 1.5; knob.stroke()
                }
            }
            return true
        }
    }
}
