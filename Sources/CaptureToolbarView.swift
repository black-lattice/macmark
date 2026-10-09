import AppKit

final class CaptureToolbarView: NSView {
    private weak var controller: EditorController?
    private let canvas: CanvasView
    private let bar = CaptureSurfaceView()
    let palette: CapturePaletteView
    private var tools: [MarkTool: NSButton] = [:]
    private var barWidth: CGFloat = 0
    private var dragPoint: CGPoint?
    var onLayoutChange: (() -> Void)?
    var paletteAbove = false { didSet { if paletteAbove != oldValue { needsLayout = true } } }
    var barFrame: CGRect { bar.frame }
    override var isFlipped: Bool { true }
    override var fittingSize: NSSize { CGSize(width: barWidth, height: palette.isHidden ? 40 : 118) }
    init(canvas: CanvasView, controller: EditorController) {
        self.canvas = canvas; self.controller = controller
        palette = CapturePaletteView(canvas: canvas)
        super.init(frame: .zero)
        appearance = NSAppearance(named: .aqua)
        bar.showsGrip = true
        addSubview(bar); addSubview(palette)
        bar.toolTip = "拖动工具栏空白处可移动位置"
        var x: CGFloat = 18
        for tool in [MarkTool.rectangle, .line, .arrow, .pen, .text, .blur, .mosaic, .select] {
            let button = CaptureIconButton.make(tool.title, icon: .forTool(tool), target: self, action: #selector(toolClicked(_:)), toggle: true)
            button.identifier = NSUserInterfaceItemIdentifier(tool.rawValue)
            button.toolTip = "\(tool.title)（\(tool.key.uppercased())）"
            place(button, at: &x)
            tools[tool] = button
        }
        divider(at: &x)
        let undo = CaptureIconButton.make("撤销", icon: .undo, target: controller, action: #selector(EditorController.undoMark))
        undo.toolTip = "撤销（⌘Z）"; place(undo, at: &x)
        let redo = CaptureIconButton.make("重做", icon: .redo, target: controller, action: #selector(EditorController.redoMark))
        redo.toolTip = "重做（⇧⌘Z）"; place(redo, at: &x)
        divider(at: &x)
        place(CaptureIconButton.make("取消", icon: .cancel, target: self, action: #selector(cancelCapture)), at: &x)
        let pin = CaptureIconButton.make("锚定截图", icon: .pin, target: controller, action: #selector(EditorController.pinImage))
        pin.toolTip = "将截图锚定在屏幕最前，右键可销毁"
        place(pin, at: &x)
        place(CaptureIconButton.make("保存 PNG", icon: .save, target: controller, action: #selector(EditorController.saveImage)), at: &x)
        let copy = CaptureIconButton.make("复制截图", icon: .copy, target: controller, action: #selector(EditorController.copyImage))
        copy.toolTip = "复制截图并完成（⌘C）"
        copy.keyEquivalent = "c"; copy.keyEquivalentModifierMask = .command
        place(copy, at: &x)
        barWidth = x + 4
        selectTool(canvas.tool)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func place(_ button: NSButton, at x: inout CGFloat) {
        button.frame = CGRect(x: x, y: 5, width: 30, height: 30)
        bar.addSubview(button); x += 32
    }
    private func divider(at x: inout CGFloat) {
        let line = NSBox(frame: CGRect(x: x + 3, y: 9, width: 1, height: 22))
        line.boxType = .separator
        bar.addSubview(line); x += 10
    }
    override func layout() {
        super.layout()
        bar.frame = CGRect(x: 0, y: paletteAbove ? bounds.height - 40 : 0, width: bounds.width, height: 40)
        let anchor = tools[canvas.tool]?.frame.minX ?? 18
        let width = 224.0
        palette.frame = CGRect(x: min(anchor, max(0, bounds.width - width)), y: paletteAbove ? 0 : 46, width: width, height: 72)
        window?.invalidateCursorRects(for: self)
    }
    func selectTool(_ tool: MarkTool) {
        let wasHidden = palette.isHidden
        for (key, button) in tools { button.state = key == tool ? .on : .off; button.needsDisplay = true }
        palette.isHidden = tool == .select
        palette.update(tool: tool)
        needsLayout = true
        if wasHidden != palette.isHidden { onLayoutChange?() }
    }
    func selectionChanged() {
        let wasHidden = palette.isHidden
        if canvas.tool == .select { palette.isHidden = canvas.selectedMark == nil }
        palette.update(tool: canvas.settingsTool)
        needsLayout = true
        if wasHidden != palette.isHidden { onLayoutChange?() }
    }
    @objc private func toolClicked(_ sender: NSButton) {
        if let id = sender.identifier?.rawValue, let tool = MarkTool(rawValue: id) { controller?.choose(tool) }
    }
    @objc private func cancelCapture() { controller?.close() }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bar.frame.contains(local) || (!palette.isHidden && palette.frame.contains(local)) else { return nil }
        return super.hitTest(point)
    }
    override func resetCursorRects() { addCursorRect(CGRect(x: 0, y: bar.frame.minY, width: 18, height: 40), cursor: .openHand) }
    override func mouseDown(with event: NSEvent) { dragPoint = event.locationInWindow }
    override func mouseDragged(with event: NSEvent) {
        guard let previous = dragPoint, let superview else { return }
        let point = event.locationInWindow
        let safe = superview.bounds.insetBy(dx: 8, dy: 8)
        let x = max(safe.minX, min(frame.minX + point.x - previous.x, safe.maxX - frame.width))
        let dy = (point.y - previous.y) * (superview.isFlipped ? -1 : 1)
        let y = max(safe.minY, min(frame.minY + dy, safe.maxY - frame.height))
        setFrameOrigin(CGPoint(x: x, y: y)); dragPoint = point
    }
    override func mouseUp(with event: NSEvent) { dragPoint = nil }
}

class CaptureSurfaceView: NSView {
    var showsGrip = false
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
        NSColor.white.setFill(); shape.fill()
        NSColor(calibratedWhite: 0.82, alpha: 1).setStroke(); shape.lineWidth = 0.5; shape.stroke()
        if showsGrip {
            NSColor.lightGray.setFill()
            for x in [CGFloat(7), 11] {
                for y in [CGFloat(15), 19, 23] { NSBezierPath(ovalIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)).fill() }
            }
        }
    }
}

final class CaptureIconButton: NSButton {
    private static let normalColor = NSColor(calibratedRed: 0.31, green: 0.35, blue: 0.41, alpha: 1)
    private var icon: CaptureToolbarIcon?
    private var isSwatch = false
    private var showsSelection = false
    private var hovering = false
    private var tracking: NSTrackingArea?
    static func make(_ title: String, icon: CaptureToolbarIcon?, target: AnyObject, action: Selector, toggle: Bool = false, swatch: Bool = false) -> CaptureIconButton {
        let button = CaptureIconButton(title: title, target: target, action: action)
        button.showsSelection = toggle
        button.icon = icon; button.isSwatch = swatch
        button.setButtonType(toggle ? .pushOnPushOff : .momentaryPushIn)
        button.isBordered = false
        button.focusRingType = .none
        button.imagePosition = .imageOnly
        if let icon { button.image = icon.image(color: normalColor) }
        button.toolTip = title; button.setAccessibilityLabel(title)
        return button
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let selected = showsSelection && state == .on
        let color: NSColor = selected || window?.firstResponder === self ? .systemBlue
            : (hovering || cell?.isHighlighted == true ? .darkGray : Self.normalColor)
        if imagePosition == .noImage {
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: color]
            let size = (title as NSString).size(withAttributes: attributes)
            (title as NSString).draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
        } else if let icon {
            icon.image(color: color).draw(in: CGRect(x: bounds.midX - 10, y: bounds.midY - 10, width: 20, height: 20))
        } else if let image {
            let glyph: NSImage
            if isSwatch { glyph = image }
            else {
                glyph = NSImage(size: image.size, flipped: false) { rect in
                    image.draw(in: rect); color.setFill(); rect.fill(using: .sourceAtop)
                    return true
                }
            }
            glyph.draw(in: CGRect(x: bounds.midX - 8, y: bounds.midY - 8, width: 16, height: 16))
            if isSwatch && selected {
                let check = NSBezierPath()
                let dy: CGFloat = isFlipped ? 1 : -1
                check.move(to: CGPoint(x: bounds.midX - 3, y: bounds.midY))
                check.line(to: CGPoint(x: bounds.midX - 1, y: bounds.midY + 2 * dy))
                check.line(to: CGPoint(x: bounds.midX + 3, y: bounds.midY - 2 * dy))
                (["黄色", "白色", "橙色", "绿色", "青色", "粉色"].contains(title) ? NSColor.black : .white).setStroke()
                check.lineWidth = 1.2; check.lineCapStyle = .round; check.stroke()
            }
        }
    }
}
