import AppKit

final class SelectionView: NSView {
    private var snapshot: NSImage?
    private var pixelSize: CGSize
    private var start: CGPoint?
    private var end: CGPoint?
    private var completedSelection: CGRect?
    private let windowFrames: [CGRect]
    private var hoveredWindow: CGRect?
    private var dragging = false
    private var mouseTracking: NSTrackingArea?
    var selection: CGRect? {
        if let completedSelection { return completedSelection }
        if dragging, let start, let end { return Geometry.rect(from: start, to: end).intersection(bounds) }
        return hoveredWindow
    }
    var onSelect: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(image: CGImage? = nil, size: CGSize, pixelSize: CGSize? = nil, windowFrames: [CGRect] = []) {
        self.windowFrames = windowFrames
        snapshot = image.map { NSImage(cgImage: $0, size: size) }
        self.pixelSize = image.map { CGSize(width: $0.width, height: $0.height) } ?? pixelSize ?? size
        super.init(frame: CGRect(origin: .zero, size: size))
        setAccessibilityLabel("截图选区，悬停选择窗口，单击进入标注，拖动自由框选，按 Escape 取消")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func updateSnapshot(_ image: CGImage) {
        snapshot = NSImage(cgImage: image, size: bounds.size)
        pixelSize = CGSize(width: image.width, height: image.height)
        needsDisplay = true
        if let selection = completedSelection {
            completedSelection = nil
            onSelect?(selection)
        }
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let mouseTracking { removeTrackingArea(mouseTracking) }
        let tracking = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                      owner: self, userInfo: nil)
        addTrackingArea(tracking); mouseTracking = tracking
    }
    func updateHoverFromMouseLocation() {
        guard let window else { return }
        updateHover(at: convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil))
    }
    private func updateHover(at point: CGPoint) {
        guard start == nil, completedSelection == nil else { return }
        let candidate = bounds.contains(point) ? windowFrames.first { $0.contains(point) } : nil
        guard candidate != hoveredWindow else { return }
        hoveredWindow = candidate
        needsDisplay = true
    }
    override func mouseMoved(with event: NSEvent) { updateHover(at: convert(event.locationInWindow, from: nil)) }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) {
        guard start == nil, completedSelection == nil else { return }
        hoveredWindow = nil; needsDisplay = true
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        completedSelection = nil
        let point = convert(event.locationInWindow, from: nil)
        updateHover(at: point)
        start = point
        end = start
        dragging = false
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        end = convert(event.locationInWindow, from: nil)
        if hypot(end!.x - start.x, end!.y - start.y) >= 3 { dragging = true }
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard let start else { return }
        end = convert(event.locationInWindow, from: nil)
        if hypot(end!.x - start.x, end!.y - start.y) >= 3 { dragging = true }
        let rect = selection
        self.start = nil; end = nil; dragging = false
        if let rect, rect.width >= 2 && rect.height >= 2 {
            completedSelection = rect
            if snapshot != nil { onSelect?(rect) }
        } else {
            updateHover(at: convert(event.locationInWindow, from: nil))
        }
        needsDisplay = true
    }
    override func rightMouseDown(with event: NSEvent) { onCancel?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() } else { super.keyDown(with: event) }
    }
    override func draw(_ dirtyRect: NSRect) {
        if let snapshot { snapshot.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil) }
        else { NSColor.clear.setFill(); dirtyRect.fill(using: .copy) }
        let shade = NSBezierPath(rect: bounds)
        if let selection {
            shade.appendRect(selection)
            shade.windingRule = .evenOdd
            NSColor.black.withAlphaComponent(0.42).setFill()
            shade.fill()
            let pixels = Geometry.cropRect(selection: selection, screenSize: bounds.size, imageSize: pixelSize)
            CaptureSelectionStyle.draw(selection: selection, pixelSize: pixels.size, within: bounds)
        } else {
            NSColor.black.withAlphaComponent(0.28).setFill()
            shade.fill()
        }
        if !dragging && completedSelection == nil {
            drawLabel("单击选择窗口 · 拖动自由框选 · Esc 取消", at: CGPoint(x: max(20, bounds.midX - 155), y: 42))
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
