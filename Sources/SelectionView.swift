import AppKit

final class SelectionView: NSView {
    private let snapshot: NSImage
    private var start: CGPoint?
    private var end: CGPoint?
    var onSelect: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(image: CGImage, size: CGSize) {
        snapshot = NSImage(cgImage: image, size: size)
        super.init(frame: CGRect(origin: .zero, size: size))
        setAccessibilityLabel("截图选区，拖动鼠标框选，按 Escape 取消")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        start = convert(event.locationInWindow, from: nil)
        end = start
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        end = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard let start else { return }
        end = convert(event.locationInWindow, from: nil)
        let rect = Geometry.rect(from: start, to: end!).intersection(bounds)
        if rect.width >= 2 && rect.height >= 2 { onSelect?(rect) }
    }
    override func rightMouseDown(with event: NSEvent) { onCancel?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() } else { super.keyDown(with: event) }
    }
    override func draw(_ dirtyRect: NSRect) {
        snapshot.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        let shade = NSBezierPath(rect: bounds)
        if let start, let end {
            let selection = Geometry.rect(from: start, to: end).intersection(bounds)
            shade.appendRect(selection)
            shade.windingRule = .evenOdd
            NSColor.black.withAlphaComponent(0.42).setFill()
            shade.fill()
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            border.stroke()
            let text = "\(Int(selection.width)) × \(Int(selection.height)) pt"
            drawLabel(text, at: CGPoint(x: min(selection.minX, max(12, bounds.width - 170)),
                                       y: max(12, selection.minY - 34)))
        } else {
            NSColor.black.withAlphaComponent(0.28).setFill()
            shade.fill()
            drawLabel("拖动框选截图 · Esc 取消", at: CGPoint(x: max(20, bounds.midX - 125), y: 42))
        }
    }
    private func drawLabel(_ text: String, at point: CGPoint) {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14, weight: .medium),
                                                       .foregroundColor: NSColor.white]
        let size = (text as NSString).size(withAttributes: attributes)
        NSColor.black.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: CGRect(x: point.x - 10, y: point.y - 6,
                                        width: size.width + 20, height: size.height + 12), xRadius: 6, yRadius: 6).fill()
        (text as NSString).draw(at: point, withAttributes: attributes)
    }
}
