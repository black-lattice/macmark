import AppKit

extension Annotation {
    var counterBounds: CGRect {
        guard let center = points.first else { return .zero }
        let size = (text as NSString).size(withAttributes: counterAttributes)
        let diameter = max((fontSize ?? 24) * 1.55, size.width + 14)
        return CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
    }
    private var counterAttributes: [NSAttributedString.Key: Any] {
        let rgb = color.usingColorSpace(.deviceRGB) ?? .black
        let brightness = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        return [.font: NSFont.monospacedDigitSystemFont(ofSize: fontSize ?? 24, weight: .bold),
                .foregroundColor: brightness > 0.65 ? NSColor.black : NSColor.white]
    }
    func drawCounter() {
        let circle = NSBezierPath(ovalIn: counterBounds)
        color.setFill(); circle.fill()
        let size = (text as NSString).size(withAttributes: counterAttributes)
        (text as NSString).draw(at: CGPoint(x: counterBounds.midX - size.width / 2,
                                          y: counterBounds.midY - size.height / 2), withAttributes: counterAttributes)
    }
}
