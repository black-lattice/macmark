import AppKit
import CoreImage

final class RedactionRenderer {
    private struct CachedRegion {
        let rect: CGRect
        let tool: MarkTool
        let strength: CGFloat
        let image: CGImage
    }
    private static let context = CIContext(options: [.cacheIntermediates: false])
    private let source: CIImage
    private let logicalSize: CGSize
    private let scaleX: CGFloat
    private let scaleY: CGFloat
    private var regions: [UUID: CachedRegion] = [:]
    init(base: CGImage, logicalSize: CGSize) {
        source = CIImage(cgImage: base)
        self.logicalSize = logicalSize
        scaleX = CGFloat(base.width) / logicalSize.width
        scaleY = CGFloat(base.height) / logicalSize.height
    }
    func draw(_ marks: [Annotation]) {
        let masks = marks.filter { $0.tool.isRedaction }
        let ids = Set(masks.map(\.id))
        regions = regions.filter { ids.contains($0.key) }
        for mark in masks {
            let rect = mark.bounds.intersection(CGRect(origin: .zero, size: logicalSize))
            guard !rect.isNull, !rect.isEmpty else { continue }
            let pixels = CGRect(x: rect.minX * scaleX, y: (logicalSize.height - rect.maxY) * scaleY,
                                width: rect.width * scaleX, height: rect.height * scaleY).integral.intersection(source.extent)
            let cached = regions[mark.id]
            let image: CGImage?
            if let cached, cached.rect == rect, cached.tool == mark.tool, cached.strength == mark.width {
                image = cached.image
            } else {
                let strength = max(1, mark.width) * max(scaleX, scaleY)
                let filtered: CIImage
                if mark.tool == .blur {
                    filtered = source.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: strength * 6])
                } else {
                    filtered = source.clampedToExtent().applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: strength * 8,
                                                                                                kCIInputCenterKey: CIVector(x: 0, y: 0)])
                }
                image = Self.context.createCGImage(filtered, from: pixels)
                if let image { regions[mark.id] = CachedRegion(rect: rect, tool: mark.tool, strength: mark.width, image: image) }
            }
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: rect).addClip()
            mark.redactionPath.addClip()
            if let image {
                let target = CGRect(x: pixels.minX / scaleX, y: logicalSize.height - pixels.maxY / scaleY,
                                    width: pixels.width / scaleX, height: pixels.height / scaleY)
                NSGraphicsContext.current?.imageInterpolation = mark.tool == .mosaic ? .none : .high
                NSImage(cgImage: image, size: target.size).draw(in: target, from: .zero, operation: .copy, fraction: 1,
                                                             respectFlipped: true, hints: nil)
            } else {
                // Keep information covered if Core Image cannot render the effect.
                NSColor.black.setFill(); NSBezierPath(rect: rect).fill()
            }
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}
