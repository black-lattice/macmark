import AppKit

final class CanvasView: NSView, NSTextFieldDelegate {
    let base: CGImage
    let logicalSize: CGSize
    private let image: NSImage
    var tool: MarkTool = .arrow { didSet { commitText(); selectedID = nil; needsDisplay = true } }
    var markColor: NSColor = .systemRed
    var markWidth: CGFloat = 3
    private(set) var marks: [Annotation] = []
    private var pending: Annotation?
    private var selectedID: UUID?
    private var previousPoint: CGPoint?
    private var beforeMove: [Annotation]?
    private var textField: NSTextField?
    private var textOrigin = CGPoint.zero
    private var textColor: NSColor = .systemRed
    private var textWidth: CGFloat = 3
    private let history = UndoManager()
    var onToolKey: ((MarkTool) -> Void)?
    var onCancel: (() -> Void)?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var undoManager: UndoManager? { history }
    var scale: CGFloat { bounds.width / logicalSize.width }
    init(base: CGImage, size: CGSize) {
        self.base = base
        logicalSize = size
        image = NSImage(cgImage: base, size: size)
        super.init(frame: CGRect(origin: .zero, size: size))
        setAccessibilityLabel("截图标注画布。A 箭头，L 直线，P 画笔，R 方框，T 文字，V 选择。")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
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
        marks.forEach(Renderer.draw)
        if let pending { Renderer.draw(pending) }
        if let selected = marks.first(where: { $0.id == selectedID }) {
            NSColor.controlAccentColor.setStroke()
            let outline = NSBezierPath(rect: selected.bounds.insetBy(dx: -5, dy: -5))
            outline.lineWidth = 1 / scale
            outline.setLineDash([4 / scale, 3 / scale], count: 2, phase: 0)
            outline.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }
    override func mouseDown(with event: NSEvent) {
        commitText()
        window?.makeFirstResponder(self)
        let p = point(event)
        if tool == .select {
            selectedID = marks.last(where: { $0.contains(p) })?.id
            previousPoint = p
            beforeMove = marks
        } else if tool == .text {
            beginText(at: p)
        } else {
            pending = Annotation(tool: tool, points: [p, p], color: markColor, width: markWidth)
        }
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        let p = point(event)
        if let id = selectedID, let previous = previousPoint, let i = marks.firstIndex(where: { $0.id == id }) {
            marks[i].move(by: CGPoint(x: p.x - previous.x, y: p.y - previous.y))
            previousPoint = p
        } else if var current = pending {
            if tool == .pen {
                if let last = current.points.last, hypot(last.x - p.x, last.y - p.y) >= 0.7 { current.points.append(p) }
            } else if event.modifierFlags.contains(.shift), let first = current.points.first {
                if tool == .rectangle {
                    let length = max(abs(p.x - first.x), abs(p.y - first.y))
                    current.points[1] = CGPoint(x: first.x + (p.x >= first.x ? length : -length),
                                               y: first.y + (p.y >= first.y ? length : -length))
                } else { current.points[1] = Geometry.constrained(p, from: first) }
            } else { current.points[1] = p }
            pending = current
        }
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if let pending {
            let old = marks
            if pending.tool == .pen || pending.bounds.width + pending.bounds.height > 1 { marks.append(pending); record(old) }
            self.pending = nil
        }
        if let beforeMove, zip(beforeMove, marks).contains(where: { $0.points != $1.points }) {
            record(beforeMove)
        }
        beforeMove = nil
        previousPoint = nil
        needsDisplay = true
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
    }
    func undo() { commitText(); history.undo(); needsDisplay = true }
    func redo() { commitText(); history.redo(); needsDisplay = true }
    private func record(_ old: [Annotation]) {
        history.registerUndo(withTarget: self) { target in
            let current = target.marks
            target.marks = old
            target.record(current)
            target.selectedID = nil
            target.needsDisplay = true
        }
    }
    private func beginText(at p: CGPoint) {
        textOrigin = p; textColor = markColor; textWidth = markWidth
        let field = NSTextField(frame: CGRect(x: p.x * scale, y: p.y * scale,
                                             width: max(80, min(280, bounds.width - p.x * scale)), height: 36))
        field.font = .systemFont(ofSize: max(16, markWidth * 6) * scale, weight: .semibold)
        field.textColor = markColor
        field.placeholderString = "输入文字，回车确认"
        field.target = self
        field.delegate = self
        field.action = #selector(finishText)
        field.setAccessibilityLabel("标注文字")
        addSubview(field)
        textField = field
        window?.makeFirstResponder(field)
    }
    @objc private func finishText() { commitText(); window?.makeFirstResponder(self) }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)), let onCancel {
            onCancel()
            return true
        }
        return false
    }
    func commitText() {
        guard let field = textField else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        field.removeFromSuperview()
        textField = nil
        if !text.isEmpty {
            let old = marks
            marks.append(Annotation(tool: .text, points: [textOrigin], color: textColor, width: textWidth, text: text))
            record(old)
        }
        needsDisplay = true
    }
    func renderedImage() -> CGImage? { commitText(); return Renderer.image(base: base, logicalSize: logicalSize, marks: marks) }
}
