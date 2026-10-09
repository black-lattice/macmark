import AppKit

enum Renderer {
    static func draw(_ mark: Annotation) {
        guard !mark.tool.isRedaction else { return }
        guard let first = mark.points.first, let last = mark.points.last else { return }
        mark.color.setStroke()
        mark.color.setFill()
        if mark.tool == .text {
            (mark.text as NSString).draw(at: first, withAttributes: mark.textAttributes)
            return
        }
        if mark.tool == .arrow {
            mark.arrowPath.fill()
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
        case .line:
            path.move(to: first)
            path.line(to: last)
        default: break
        }
        path.stroke()
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
        RedactionRenderer(base: base, logicalSize: logicalSize).draw(marks)
        marks.filter { !$0.tool.isRedaction }.forEach(draw)
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }
    static func png(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
