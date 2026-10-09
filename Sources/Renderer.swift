import AppKit

enum Renderer {
    static func draw(_ mark: Annotation) {
        guard let first = mark.points.first, let last = mark.points.last else { return }
        mark.color.setStroke()
        mark.color.setFill()
        if mark.tool == .text {
            (mark.text as NSString).draw(at: first, withAttributes: mark.textAttributes)
            return
        }
        let path = NSBezierPath()
        path.lineWidth = mark.width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        switch mark.tool {
        case .rectangle:
            path.appendRect(Geometry.rect(from: first, to: last))
        case .pen:
            path.move(to: first)
            for point in mark.points.dropFirst() { path.line(to: point) }
        case .arrow, .line:
            path.move(to: first)
            path.line(to: last)
        default: break
        }
        path.stroke()
        if mark.tool == .arrow {
            let angle = atan2(last.y - first.y, last.x - first.x)
            let length = min(hypot(last.x - first.x, last.y - first.y) * 0.45, max(12, mark.width * 4))
            let head = NSBezierPath()
            head.move(to: last)
            for delta in [-CGFloat.pi / 6, CGFloat.pi / 6] {
                head.line(to: CGPoint(x: last.x - cos(angle + delta) * length,
                                     y: last.y - sin(angle + delta) * length))
            }
            head.close()
            head.fill()
        }
    }
    static func image(base: CGImage, logicalSize: CGSize, marks: [Annotation]) -> CGImage? {
        guard let context = CGContext(data: nil, width: base.width, height: base.height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(base, in: CGRect(x: 0, y: 0, width: base.width, height: base.height))
        context.translateBy(x: 0, y: CGFloat(base.height))
        context.scaleBy(x: CGFloat(base.width) / logicalSize.width,
                        y: -CGFloat(base.height) / logicalSize.height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        marks.forEach(draw)
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }
    static func png(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
