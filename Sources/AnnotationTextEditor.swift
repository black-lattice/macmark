import AppKit

final class AnnotationTextEditor: NSView, NSTextViewDelegate {
    let textView = AnnotationTextView()
    private let history = UndoManager()
    private var anchor = CGPoint.zero
    private var available = CGRect.zero
    private var contentSize = CGSize.zero
    private var scale: CGFloat = 1
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?
    override var isFlipped: Bool { true }
    init(font: NSFont) {
        super.init(frame: .zero)
        clipsToBounds = true
        textView.font = font
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.minSize = .zero
        textView.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        // Keep the text anchored to the image; only explicit returns create new lines.
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = textView.maxSize
        textView.delegate = self
        textView.onCommit = { [weak self] in self?.onCommit?() }
        textView.setAccessibilityLabel("标注文字")
        textView.setAccessibilityHelp("Shift 加回车换行，回车完成；点击画布或切换工具也会完成。")
        addSubview(textView)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func place(at point: CGPoint, within bounds: CGRect, scale: CGFloat = 1) {
        anchor = point; available = bounds; self.scale = scale
        resizeToFit()
    }
    func updateFont(_ font: NSFont) { textView.font = font; resizeToFit() }
    private func resizeToFit() {
        let font = textView.font ?? .systemFont(ofSize: 18)
        guard let manager = textView.layoutManager, let container = textView.textContainer else { return }
        manager.ensureLayout(for: container)
        let used = manager.usedRect(for: container)
        // The extra fragment reserves space for the caret after a trailing newline.
        contentSize = CGSize(width: ceil(used.width),
                             height: ceil(max(manager.defaultLineHeight(for: font), used.maxY,
                                              manager.extraLineFragmentRect.maxY) + textView.textContainerInset.height * 2))
        contentSize.width = max(24, contentSize.width + 2)
        let width = max(0, min(available.maxX - anchor.x, contentSize.width * scale))
        let height = max(0, min(available.maxY - anchor.y, contentSize.height * scale))
        frame = CGRect(origin: anchor, size: CGSize(width: width, height: height))
        setBoundsSize(CGSize(width: width / scale, height: height / scale))
        needsLayout = true
        layoutSubtreeIfNeeded()
    }
    override func layout() {
        super.layout()
        textView.setFrameSize(contentSize)
    }
    func textDidChange(_ notification: Notification) { resizeToFit() }
    func undoManager(for view: NSTextView) -> UndoManager? { history }
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            onCancel?(); return true
        }
        return false
    }
}

final class AnnotationTextView: NSTextView {
    var onCommit: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if (event.keyCode == 36 || event.keyCode == 76), !hasMarkedText() {
            if event.modifierFlags.contains(.shift) { insertNewlineIgnoringFieldEditor(self) }
            else { onCommit?() }
            return
        }
        super.keyDown(with: event)
    }
}
