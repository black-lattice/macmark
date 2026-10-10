import AppKit

struct CaptureEditingContext {
    let window: NSWindow
    let snapshot: CGImage
    let selection: CGRect
}

final class CaptureEditorView: NSView {
    private let snapshot: NSImage
    private let source: CGImage
    private let screenSize: CGSize
    private let canvas: CanvasView
    private(set) var selection: CGRect
    private var resizeDrag: (corner: Int, selection: CGRect, start: CGPoint)?
    private let toolbar: CaptureToolbarView
    private let outline = CaptureOutlineView()
    var onCancel: (() -> Void)?
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    init(context: CaptureEditingContext, canvas: CanvasView, toolbar: CaptureToolbarView) {
        let size = context.window.contentView?.bounds.size ?? context.window.frame.size
        snapshot = NSImage(cgImage: context.snapshot, size: size)
        source = context.snapshot
        screenSize = size
        self.canvas = canvas
        selection = context.selection
        self.toolbar = toolbar
        super.init(frame: CGRect(origin: .zero, size: size))
        setAccessibilityLabel("截图原位标注，拖动选区四角调整大小，Escape 或右键取消")
        // Keep the fixed screen snapshot visible instead of rescaling a pixel-rounded crop during resize.
        canvas.drawsBaseImage = false
        canvas.frame = selection
        addSubview(canvas)
        outline.frame = bounds
        outline.selection = selection
        outline.pixelSize = CGSize(width: canvas.base.width, height: canvas.base.height)
        addSubview(outline)
        outline.onDragStart = { [weak self] corner, point in self?.beginResize(corner: corner, at: point) }
        outline.onDrag = { [weak self] point in self?.resize(to: point) }
        outline.onDragEnd = { [weak self] point in self?.endResize(at: point) }
        addSubview(toolbar, positioned: .below, relativeTo: outline)
        toolbar.onLayoutChange = { [weak self] in
            self?.needsLayout = true
            self?.layoutSubtreeIfNeeded()
        }
        needsLayout = true
        layoutSubtreeIfNeeded()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        let placement = Self.toolbarPlacement(selection: selection, size: toolbar.fittingSize, within: bounds)
        toolbar.paletteAbove = placement.paletteAbove
        toolbar.frame = placement.frame
        let bar = CGRect(x: placement.frame.minX,
                         y: placement.paletteAbove ? placement.frame.maxY - 40 : placement.frame.minY,
                         width: placement.frame.width, height: 40)
        outline.frame = bounds
        outline.labelBelow = CaptureSelectionStyle.labelFrame(selection: selection, pixelSize: outline.pixelSize, within: bounds).intersects(bar)
        outline.needsDisplay = true
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }
    override func mouseDown(with event: NSEvent) {
        canvas.commitText()
        window?.makeFirstResponder(canvas)
    }
    private func beginResize(corner: Int, at point: CGPoint) {
        canvas.commitText()
        window?.makeFirstResponder(canvas)
        resizeDrag = (corner, selection, point)
    }
    private func resize(to point: CGPoint) {
        guard let drag = resizeDrag else { return }
        let corners = CaptureSelectionStyle.corners(of: drag.selection)
        let corner = corners[drag.corner]
        let anchor = corners[(drag.corner + 2) % 4]
        let proposed = CGPoint(x: corner.x + point.x - drag.start.x, y: corner.y + point.y - drag.start.y)
        // Keep the opposite corner fixed and a usable minimum of two screen points.
        let end = CGPoint(x: corner.x < anchor.x ? max(0, min(anchor.x - 2, proposed.x)) : min(screenSize.width, max(anchor.x + 2, proposed.x)),
                          y: corner.y < anchor.y ? max(0, min(anchor.y - 2, proposed.y)) : min(screenSize.height, max(anchor.y + 2, proposed.y)))
        applySelection(Geometry.rect(from: anchor, to: end))
    }
    private func endResize(at point: CGPoint) {
        guard let drag = resizeDrag else { return }
        resize(to: point)
        resizeDrag = nil
        if selection != drag.selection { recordSelection(drag.selection) }
        window?.makeFirstResponder(canvas)
    }
    private func applySelection(_ rect: CGRect) {
        guard rect != selection else { return }
        let pixels = Geometry.cropRect(selection: rect, screenSize: screenSize,
                                       imageSize: CGSize(width: source.width, height: source.height))
        guard let cropped = source.cropping(to: pixels) else { return }
        selection = rect
        outline.selection = rect
        outline.pixelSize = pixels.size
        canvas.updateCapture(base: cropped, frame: rect)
        needsDisplay = true; needsLayout = true
        layoutSubtreeIfNeeded()
        window?.invalidateCursorRects(for: outline)
    }
    private func recordSelection(_ old: CGRect) {
        canvas.undoManager?.registerUndo(withTarget: canvas) { [weak self] _ in
            guard let self else { return }
            let current = self.selection
            self.applySelection(old)
            self.recordSelection(current)
        }
    }
    override func rightMouseDown(with event: NSEvent) { onCancel?() }
    override func draw(_ dirtyRect: NSRect) {
        snapshot.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        let shade = NSBezierPath(rect: bounds)
        shade.appendRect(selection)
        shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.42).setFill()
        shade.fill()
    }
    // Flipped, display-local coordinates also work for screens with negative global origins.
    static func toolbarFrame(selection: CGRect, size: CGSize, within bounds: CGRect) -> CGRect {
        toolbarPlacement(selection: selection, size: size, within: bounds).frame
    }
    private static func toolbarPlacement(selection: CGRect, size: CGSize, within bounds: CGRect) -> (frame: CGRect, paletteAbove: Bool) {
        let safe = bounds.insetBy(dx: 8, dy: 8)
        let width = min(size.width, safe.width)
        let height = min(size.height, safe.height)
        let x = max(safe.minX, min(selection.midX - width / 2, safe.maxX - width))
        let y: CGFloat
        let paletteAbove: Bool
        let barHeight = min(40, height)
        if selection.maxY + 8 + height <= safe.maxY {
            y = selection.maxY + 8
            paletteAbove = false
        } else if selection.minY - 8 - height >= safe.minY {
            y = selection.minY - 8 - height
            paletteAbove = true
        } else if selection.maxY + 8 + barHeight <= safe.maxY {
            // Keep the main bar outside the capture when only the palette needs to overlap.
            y = selection.maxY + 8 - (height - barHeight)
            paletteAbove = true
        } else if selection.minY - 8 - barHeight >= safe.minY {
            y = selection.minY - 8 - barHeight
            paletteAbove = false
        } else {
            y = max(safe.minY, min(selection.maxY - height - 8, safe.maxY - height))
            paletteAbove = true
        }
        return (CGRect(x: x, y: max(safe.minY, min(y, safe.maxY - height)), width: width, height: height), paletteAbove)
    }
}

enum CaptureSelectionStyle {
    static let blue = NSColor(calibratedRed: 0.08, green: 0.42, blue: 0.94, alpha: 1)
    static func corners(of selection: CGRect) -> [CGPoint] {
        [CGPoint(x: selection.minX, y: selection.minY), CGPoint(x: selection.maxX, y: selection.minY),
         CGPoint(x: selection.maxX, y: selection.maxY), CGPoint(x: selection.minX, y: selection.maxY)]
    }
    static func labelFrame(selection: CGRect, pixelSize: CGSize, within bounds: CGRect, below: Bool = false) -> CGRect {
        let text = "\(Int(pixelSize.width)) × \(Int(pixelSize.height))"
        let size = (text as NSString).size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)])
        return CGRect(x: max(4, min(selection.minX, bounds.maxX - size.width - 16)),
                      y: below ? min(bounds.maxY - 23, selection.maxY + 4) : max(4, selection.minY - 23),
                      width: size.width + 12, height: 19)
    }
    static func draw(selection: CGRect, pixelSize: CGSize, within bounds: CGRect, labelBelow: Bool = false) {
        let border = NSBezierPath(rect: selection)
        // A white keyline and soft shadow separate the blue from light, dark and busy backgrounds.
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = .zero
        shadow.set()
        NSColor.white.withAlphaComponent(0.95).setStroke()
        border.lineWidth = 4
        border.stroke()
        NSGraphicsContext.restoreGraphicsState()
        blue.setStroke()
        border.lineWidth = 2
        border.stroke()
        let brackets = NSBezierPath()
        let cornerLength = min(18, min(selection.width, selection.height) / 2)
        for (x, dx) in [(selection.minX, CGFloat(1)), (selection.maxX, CGFloat(-1))] {
            for (y, dy) in [(selection.minY, CGFloat(1)), (selection.maxY, CGFloat(-1))] {
                brackets.move(to: CGPoint(x: x + dx * cornerLength, y: y))
                brackets.line(to: CGPoint(x: x, y: y))
                brackets.line(to: CGPoint(x: x, y: y + dy * cornerLength))
            }
        }
        brackets.lineJoinStyle = .round
        brackets.lineCapStyle = .round
        NSColor.white.setStroke()
        brackets.lineWidth = 6; brackets.stroke()
        blue.setStroke()
        brackets.lineWidth = 4; brackets.stroke()
        let text = "\(Int(pixelSize.width)) × \(Int(pixelSize.height))"
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
                                                       .foregroundColor: NSColor.white]
        let label = labelFrame(selection: selection, pixelSize: pixelSize, within: bounds, below: labelBelow)
        blue.setFill()
        NSBezierPath(roundedRect: label, xRadius: 3, yRadius: 3).fill()
        (text as NSString).draw(at: CGPoint(x: label.minX + 6, y: label.minY + 2), withAttributes: attributes)
    }
}

private final class CaptureOutlineView: NSView {
    var selection = CGRect.zero
    var pixelSize = CGSize.zero
    var labelBelow = false
    var onDragStart: ((Int, CGPoint) -> Void)?
    var onDrag: ((CGPoint) -> Void)?
    var onDragEnd: ((CGPoint) -> Void)?
    private var draggedCorner: Int?
    override var isFlipped: Bool { true }
    private func handleRect(at point: CGPoint) -> CGRect {
        CGRect(x: point.x - 8, y: point.y - 8, width: 16, height: 16).intersection(bounds)
    }
    private func corner(at point: CGPoint) -> Int? {
        let corners = CaptureSelectionStyle.corners(of: selection)
        return corners.indices.filter { handleRect(at: corners[$0]).contains(point) }.min {
            hypot(corners[$0].x - point.x, corners[$0].y - point.y) < hypot(corners[$1].x - point.x, corners[$1].y - point.y)
        }
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        corner(at: convert(point, from: superview)) == nil ? nil : self
    }
    override func resetCursorRects() {
        for (index, point) in CaptureSelectionStyle.corners(of: selection).enumerated() {
            addCursorRect(handleRect(at: point), cursor: AnnotationCursor.resize(corner: index))
        }
    }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let corner = corner(at: point) else { return }
        draggedCorner = corner
        AnnotationCursor.resize(corner: corner).set()
        onDragStart?(corner, point)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let corner = draggedCorner else { return }
        onDrag?(convert(event.locationInWindow, from: nil))
        AnnotationCursor.resize(corner: corner).set()
    }
    override func mouseUp(with event: NSEvent) {
        guard draggedCorner != nil else { return }
        onDragEnd?(convert(event.locationInWindow, from: nil))
        draggedCorner = nil
    }
    override func rightMouseDown(with event: NSEvent) { superview?.rightMouseDown(with: event) }
    override func draw(_ dirtyRect: NSRect) {
        CaptureSelectionStyle.draw(selection: selection, pixelSize: pixelSize, within: bounds, labelBelow: labelBelow)
    }
}
