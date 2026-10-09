import AppKit

struct CaptureEditingContext {
    let window: NSWindow
    let snapshot: CGImage
    let selection: CGRect
}

final class CaptureEditorView: NSView {
    private let snapshot: NSImage
    private let selection: CGRect
    private let toolbar: CaptureToolbarView
    private let outline = CaptureOutlineView()
    var onCancel: (() -> Void)?
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    init(context: CaptureEditingContext, canvas: CanvasView, toolbar: CaptureToolbarView) {
        let size = context.window.contentView?.bounds.size ?? context.window.frame.size
        snapshot = NSImage(cgImage: context.snapshot, size: size)
        selection = context.selection
        self.toolbar = toolbar
        super.init(frame: CGRect(origin: .zero, size: size))
        setAccessibilityLabel("截图原位标注，Escape 或右键取消")
        canvas.frame = selection
        addSubview(canvas)
        outline.frame = bounds
        outline.selection = selection
        outline.pixelSize = CGSize(width: canvas.base.width, height: canvas.base.height)
        addSubview(outline)
        addSubview(toolbar)
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
        if let canvas = subviews.first as? CanvasView {
            canvas.commitText()
            window?.makeFirstResponder(canvas)
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
    static let blue = NSColor(calibratedRed: 0.22, green: 0.64, blue: 1, alpha: 1)
    static func labelFrame(selection: CGRect, pixelSize: CGSize, within bounds: CGRect, below: Bool = false) -> CGRect {
        let text = "\(Int(pixelSize.width)) × \(Int(pixelSize.height))"
        let size = (text as NSString).size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)])
        return CGRect(x: max(4, min(selection.minX, bounds.maxX - size.width - 16)),
                      y: below ? min(bounds.maxY - 23, selection.maxY + 4) : max(4, selection.minY - 23),
                      width: size.width + 12, height: 19)
    }
    static func draw(selection: CGRect, pixelSize: CGSize, within bounds: CGRect, labelBelow: Bool = false) {
        blue.setStroke()
        let border = NSBezierPath(rect: selection.insetBy(dx: -0.5, dy: -0.5))
        border.lineWidth = 1
        border.stroke()
        // Corner brackets mark the boundary without implying draggable resize handles.
        let corners = NSBezierPath()
        for (x, dx) in [(selection.minX, CGFloat(1)), (selection.maxX, CGFloat(-1))] {
            for (y, dy) in [(selection.minY, CGFloat(1)), (selection.maxY, CGFloat(-1))] {
                corners.move(to: CGPoint(x: x + dx * 7, y: y))
                corners.line(to: CGPoint(x: x, y: y))
                corners.line(to: CGPoint(x: x, y: y + dy * 7))
            }
        }
        corners.lineWidth = 2; corners.stroke()
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
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        CaptureSelectionStyle.draw(selection: selection, pixelSize: pixelSize, within: bounds, labelBelow: labelBelow)
    }
}
