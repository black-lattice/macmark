import AppKit

final class BrushCursorPreview: NSView {
    private(set) var center: CGPoint?
    private(set) var diameter: CGFloat = 0
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func update(center: CGPoint?, diameter: CGFloat) {
        guard self.center != center || self.diameter != diameter else { return }
        if let old = circle { setNeedsDisplay(old.insetBy(dx: -3, dy: -3)) }
        self.center = center; self.diameter = diameter
        if let circle { setNeedsDisplay(circle.insetBy(dx: -3, dy: -3)) }
    }
    private var circle: CGRect? {
        center.map { CGRect(x: $0.x - diameter / 2, y: $0.y - diameter / 2, width: diameter, height: diameter) }
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let circle else { return }
        let ring = NSBezierPath(ovalIn: circle)
        NSColor.white.setStroke(); ring.lineWidth = 3; ring.stroke()
        NSColor.black.setStroke(); ring.lineWidth = 1; ring.stroke()
    }
}
