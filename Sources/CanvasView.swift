import AppKit

final class CanvasView: NSView {
    let base: CGImage
    let logicalSize: CGSize
    private let image: NSImage
    var tool: MarkTool = .arrow { didSet { commitText(); selectedID = nil; needsDisplay = true; refreshCursor(); onSelectionChange?() } }
    var markColor: NSColor = .systemRed
    var markWidth: CGFloat = 3
    var redactionStrength: CGFloat = 3
    var redactionMode: RedactionMode = .region { didSet { selectedID = nil; needsDisplay = true; refreshCursor() } }
    var redactionBrushSize: CGFloat = 24 { didSet { refreshCursor() } }
    var textSize: CGFloat = 18
    private var beforeStyleChange: [Annotation]?
    private let textInput = CanvasTextInput()
    private let brushPreview = BrushCursorPreview()
    private(set) var marks: [Annotation] = []
    private var pending: Annotation?
    private var selectedID: UUID?
    private var previousPoint: CGPoint?
    private var beforeMove: [Annotation]?
    private var selectedHandle: Int?
    private var dragCursor: NSCursor?
    private var tracking: NSTrackingArea?
    private let history = UndoManager()
    private let redactions: RedactionRenderer
    var onToolKey: ((MarkTool) -> Void)?
    var onCancel: (() -> Void)?
    var onSelectionChange: (() -> Void)?
    var selectedMark: Annotation? { marks.first { $0.id == selectedID } }
    var settingsTool: MarkTool { selectedMark?.tool ?? tool }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var undoManager: UndoManager? { history }
    var scale: CGFloat { bounds.width / logicalSize.width }
    init(base: CGImage, size: CGSize) {
        self.base = base
        logicalSize = size
        image = NSImage(cgImage: base, size: size)
        redactions = RedactionRenderer(base: base, logicalSize: size)
        super.init(frame: CGRect(origin: .zero, size: size))
        brushPreview.frame = bounds; brushPreview.autoresizingMask = [.width, .height]; addSubview(brushPreview)
        setAccessibilityLabel("截图标注画布。A 箭头，L 直线，P 画笔，R 方框，T 文字，B 高斯模糊，M 马赛克，V 选择。")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private var defaultCursor: NSCursor {
        tool.isRedaction && redactionMode == .brush ? AnnotationCursor.brush : (tool == .select ? .arrow : (tool == .text ? .iBeam : .crosshair))
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: defaultCursor) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited, .cursorUpdate], owner: self)
        addTrackingArea(area); tracking = area
    }
    private func editableHit(at p: CGPoint) -> (mark: Annotation, handle: Int?)? {
        if tool.isRedaction && redactionMode == .brush { return nil }
        guard tool == .select || tool == .arrow || tool == .line || tool.isRegion else { return nil }
        let selected = marks.first { $0.id == selectedID }
        if let mark = selected, let handle = mark.handle(at: p, tolerance: 8 / scale) { return (mark, handle) }
        guard let mark = marks.last(where: {
            (tool == .select || !$0.editingHandles.isEmpty)
                && ($0.handle(at: p, tolerance: 8 / scale) != nil || $0.contains(p))
        }) else { return nil }
        return (mark, mark.handle(at: p, tolerance: 8 / scale))
    }
    private func updateCursor(at location: CGPoint) {
        if let dragCursor { dragCursor.set(); return }
        guard let content = window?.contentView,
              content.hitTest(content.superview?.convert(location, from: nil) ?? location) === self else {
            brushPreview.update(center: nil, diameter: 0)
            if tool.isRedaction && redactionMode == .brush { NSCursor.arrow.set() }
            return
        }
        let local = convert(location, from: nil)
        let brushSize = pending?.isBrushRedaction == true ? pending!.brushSize : redactionBrushSize
        brushPreview.update(center: tool.isRedaction && redactionMode == .brush ? local : nil, diameter: brushSize * scale)
        if let hit = editableHit(at: CGPoint(x: local.x / scale, y: local.y / scale)) {
            if let handle = hit.handle { AnnotationCursor.resize(mark: hit.mark, handle: handle).set() }
            else { NSCursor.openHand.set() }
        } else { defaultCursor.set() }
    }
    private func refreshCursor() {
        window?.invalidateCursorRects(for: self)
        if let window { updateCursor(at: window.mouseLocationOutsideOfEventStream) }
    }
    override func cursorUpdate(with event: NSEvent) { updateCursor(at: event.locationInWindow) }
    override func mouseMoved(with event: NSEvent) { updateCursor(at: event.locationInWindow) }
    override func mouseEntered(with event: NSEvent) { updateCursor(at: event.locationInWindow) }
    override func mouseExited(with event: NSEvent) { brushPreview.update(center: nil, diameter: 0); (dragCursor ?? .arrow).set() }
    private func point(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: max(0, min(logicalSize.width, p.x / scale)),
                       y: max(0, min(logicalSize.height, p.y / scale)))
    }
    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.scale(by: scale)
        transform.concat()
        redactions.draw(marks + (pending.map { [$0] } ?? []))
        marks.filter { !$0.tool.isRedaction }.forEach(Renderer.draw)
        if let pending, !pending.tool.isRedaction { Renderer.draw(pending) }
        if let selected = marks.first(where: { $0.id == selectedID }), selected.tool != .text || tool == .select {
            NSColor.controlAccentColor.setStroke()
            if selected.editingHandles.isEmpty || selected.tool.isRegion {
                let outline = selected.selectionPath(scale: scale)
                outline.lineWidth = 1 / scale
                outline.setLineDash([4 / scale, 3 / scale], count: 2, phase: 0)
                outline.stroke()
            }
            for point in selected.editingHandles {
                let handle = NSBezierPath(ovalIn: CGRect(x: point.x - 4 / scale, y: point.y - 4 / scale,
                                                        width: 8 / scale, height: 8 / scale))
                NSColor.white.setFill(); handle.fill()
                handle.lineWidth = 1.5 / scale; handle.stroke()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }
    override func mouseDown(with event: NSEvent) {
        commitText()
        window?.makeFirstResponder(self)
        let p = point(event)
        selectedHandle = nil
        if let hit = editableHit(at: p) {
            selectedID = hit.mark.id
            selectedHandle = hit.handle
            dragCursor = hit.handle.map { AnnotationCursor.resize(mark: hit.mark, handle: $0) } ?? .closedHand
            previousPoint = p
            beforeMove = marks
        } else {
            selectedID = nil
            if tool == .text { textInput.begin(on: self, at: p) }
            else if tool != .select {
                let brush = tool.isRedaction && redactionMode == .brush
                pending = Annotation(tool: tool, points: brush ? [p] : [p, p], color: markColor,
                                     width: tool.isRedaction ? redactionStrength : markWidth,
                                     redactionMode: redactionMode, brushSize: redactionBrushSize)
            }
        }
        updateCursor(at: event.locationInWindow)
        needsDisplay = true; onSelectionChange?()
    }
    override func mouseDragged(with event: NSEvent) {
        let p = point(event)
        if let id = selectedID, let previous = previousPoint, let i = marks.firstIndex(where: { $0.id == id }) {
            if let handle = selectedHandle, let original = beforeMove?.first(where: { $0.id == id }) {
                marks[i].resize(handle: handle, to: p, from: original, constrained: event.modifierFlags.contains(.shift))
            } else { marks[i].move(by: CGPoint(x: p.x - previous.x, y: p.y - previous.y)) }
            previousPoint = p
        } else if var current = pending {
            if current.tool == .pen || current.isBrushRedaction {
                if let last = current.points.last, hypot(last.x - p.x, last.y - p.y) >= 0.7 { current.points.append(p) }
            } else if event.modifierFlags.contains(.shift), let first = current.points.first {
                if tool.isRegion {
                    let length = max(abs(p.x - first.x), abs(p.y - first.y))
                    current.points[1] = CGPoint(x: first.x + (p.x >= first.x ? length : -length),
                                               y: first.y + (p.y >= first.y ? length : -length))
                } else { current.points[1] = Geometry.constrained(p, from: first) }
            } else { current.points[1] = p }
            pending = current
        }
        updateCursor(at: event.locationInWindow)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if var pending {
            if pending.isBrushRedaction, let last = pending.points.last {
                let end = point(event)
                if last != end { pending.points.append(end) }
            }
            let old = marks
            if pending.tool == .pen || pending.bounds.width + pending.bounds.height > 1 {
                marks.append(pending); record(old)
                selectedID = pending.tool == .pen || pending.tool.isRedaction || !pending.editingHandles.isEmpty ? pending.id : nil
            }
            self.pending = nil
        }
        if let beforeMove, zip(beforeMove, marks).contains(where: { $0.points != $1.points }) {
            record(beforeMove)
        }
        beforeMove = nil
        previousPoint = nil
        selectedHandle = nil
        dragCursor = nil
        updateCursor(at: event.locationInWindow)
        needsDisplay = true; onSelectionChange?()
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 { deleteSelected(); return }
        if event.keyCode == 53 {
            if let onCancel { onCancel() } else { selectedID = nil; needsDisplay = true }
            return
        }
        if !event.modifierFlags.contains(.command), let key = event.charactersIgnoringModifiers?.lowercased(),
           let next = MarkTool.allCases.first(where: { $0.key == key }) { onToolKey?(next); return }
        super.keyDown(with: event)
    }
    override func rightMouseDown(with event: NSEvent) {
        if let onCancel { onCancel() } else { super.rightMouseDown(with: event) }
    }
    override func cancelOperation(_ sender: Any?) {
        if let onCancel { onCancel() } else { super.cancelOperation(sender) }
    }
    func deleteSelected() {
        guard let id = selectedID else { return }
        let old = marks
        marks.removeAll { $0.id == id }
        record(old)
        selectedID = nil
        needsDisplay = true
        refreshCursor(); onSelectionChange?()
    }
    func undo() { commitText(); history.undo(); needsDisplay = true }
    func redo() { commitText(); history.redo(); needsDisplay = true }
    func beginStyleChange() { beforeStyleChange = marks }
    func endStyleChange() {
        if let old = beforeStyleChange, zip(old, marks).contains(where: { $0.width != $1.width || $0.fontSize != $1.fontSize }) { record(old) }
        beforeStyleChange = nil
    }
    private func changeSelectedStyle(_ edit: (inout Annotation) -> Void) {
        guard let index = marks.firstIndex(where: { $0.id == selectedID }) else { return }
        let old = marks; edit(&marks[index])
        if old[index].width == marks[index].width && old[index].fontSize == marks[index].fontSize { return }
        if beforeStyleChange == nil { record(old) }
        needsDisplay = true; refreshCursor()
    }
    func setMarkWidth(_ width: CGFloat) {
        commitText(); markWidth = width
        changeSelectedStyle { if !$0.tool.isRedaction && $0.tool != .text { $0.width = width } }
    }
    func setTextSize(_ size: CGFloat) {
        textSize = size; textInput.updateFont(size: size, scale: scale)
        changeSelectedStyle { if $0.tool == .text { $0.fontSize = size } }
    }
    func setRedactionStrength(_ strength: CGFloat) {
        redactionStrength = strength
        changeSelectedStyle { if $0.tool.isRedaction { $0.width = strength } }
    }
    func restoreEditingFocus() { textInput.restoreFocus(on: self) }
    private func record(_ old: [Annotation]) {
        history.registerUndo(withTarget: self) { target in
            let current = target.marks
            target.marks = old
            target.record(current)
            target.selectedID = nil
            target.needsDisplay = true
            target.refreshCursor(); target.onSelectionChange?()
        }
    }
    func commitText() {
        guard let mark = textInput.commit(on: self) else { return }
        let old = marks; marks.append(mark); record(old); selectedID = mark.id
        needsDisplay = true; onSelectionChange?()
    }
    func renderedImage() -> CGImage? { commitText(); return Renderer.image(base: base, logicalSize: logicalSize, marks: marks) }
}
