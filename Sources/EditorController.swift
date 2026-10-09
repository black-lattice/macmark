import AppKit
import UniformTypeIdentifiers

final class EditorController: NSWindowController, NSWindowDelegate {
    let canvas: CanvasView
    private let scroll = NSScrollView()
    private var toolButtons: [MarkTool: NSButton] = [:]
    private var colorButtons: [NSButton] = []
    private let colorCaption = NSTextField(labelWithString: "颜色")
    private let widthSelector = AnnotationSizeSlider()
    private let redactionModeSelector = NSSegmentedControl(labels: ["框选", "涂抹"], trackingMode: .selectOne, target: nil, action: nil)
    private let brushSizeSelector = AnnotationSizeSlider()
    private var zoom: CGFloat = 1
    private let isCapture: Bool
    private var captureToolbar: CaptureToolbarView?
    var onClose: (() -> Void)?
    var onPin: ((CGImage, CGSize, CGRect) -> Void)?
    init(image: CGImage, size: CGSize, captureContext: CaptureEditingContext? = nil) {
        canvas = CanvasView(base: image, size: size)
        isCapture = captureContext != nil
        let available = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1200, height: 800)
        let frame = CGRect(x: 0, y: 0, width: min(1040, available.width - 40), height: min(760, available.height - 40))
        let window = captureContext?.window ?? NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "轻截 · 截图标注"
        if !isCapture { window.minSize = CGSize(width: 780, height: 420) }
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildUI(captureContext: captureContext)
        canvas.onToolKey = { [weak self] tool in self?.choose(tool) }
        canvas.onSelectionChange = { [weak self] in self?.captureToolbar?.selectionChanged(); self?.updateOptions() }
        if isCapture { canvas.onCancel = { [weak self] in self?.close() } }
        else { window.center() }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if !isCapture { fit() }
        window.makeFirstResponder(canvas)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func buildUI(captureContext: CaptureEditingContext?) {
        if let captureContext {
            let toolbar = CaptureToolbarView(canvas: canvas, controller: self)
            captureToolbar = toolbar
            let overlay = CaptureEditorView(context: captureContext, canvas: canvas, toolbar: toolbar)
            overlay.onCancel = { [weak self] in self?.close() }
            window?.contentView = overlay
            overlay.layoutSubtreeIfNeeded()
            return
        }
        let content = EditorBackgroundView()
        window?.contentView = content
        let tools = NSStackView()
        tools.spacing = 4
        for tool in MarkTool.allCases {
            let button = NSButton(title: tool.title, target: self, action: #selector(toolClicked(_:)))
            button.image = NSImage(systemSymbolName: tool.symbol, accessibilityDescription: tool.title)
            button.imagePosition = .imageLeading
            button.bezelStyle = .rounded
            button.setButtonType(.pushOnPushOff)
            button.identifier = NSUserInterfaceItemIdentifier(tool.rawValue)
            button.toolTip = "\(tool.title)（\(tool.key.uppercased())）"
            button.setAccessibilityLabel(button.toolTip)
            tools.addArrangedSubview(button)
            toolButtons[tool] = button
        }
        toolButtons[.arrow]?.state = .on
        tools.addArrangedSubview(NSView())
        let undo = button("撤销", symbol: "arrow.uturn.backward", action: #selector(undoMark))
        undo.toolTip = "撤销（⌘Z）"
        tools.addArrangedSubview(undo)
        let redo = button("重做", symbol: "arrow.uturn.forward", action: #selector(redoMark))
        redo.toolTip = "重做（⇧⌘Z）"
        tools.addArrangedSubview(redo)
        let options = NSStackView()
        options.spacing = 6
        options.addArrangedSubview(colorCaption)
        let colors: [(String, NSColor)] = [("红色", .systemRed), ("橙色", .systemOrange),
                                          ("蓝色", .systemBlue), ("黑色", .black), ("白色", .white)]
        for (index, entry) in colors.enumerated() {
            let b = NSButton(title: entry.0, target: self, action: #selector(colorClicked(_:)))
            b.bezelStyle = .rounded
            b.setButtonType(.pushOnPushOff)
            b.contentTintColor = entry.1
            b.setAccessibilityLabel(entry.0)
            b.tag = index
            b.toolTip = entry.0
            b.state = index == 0 ? .on : .off
            colorButtons.append(b)
            options.addArrangedSubview(b)
        }
        let width = widthSelector
        width.bindStyle(to: canvas); width.configureStyle(for: canvas)
        options.addArrangedSubview(width)
        redactionModeSelector.target = self; redactionModeSelector.action = #selector(redactionModeChanged(_:))
        redactionModeSelector.selectedSegment = canvas.redactionMode.rawValue
        redactionModeSelector.isHidden = true; redactionModeSelector.setAccessibilityLabel("遮挡方式")
        brushSizeSelector.bindBrush(to: canvas)
        brushSizeSelector.configure(title: "笔刷", value: canvas.redactionBrushSize, range: 6...200, step: 1)
        brushSizeSelector.isHidden = true
        options.addArrangedSubview(redactionModeSelector); options.addArrangedSubview(brushSizeSelector)
        options.addArrangedSubview(NSView())
        options.addArrangedSubview(button("适应", symbol: "arrow.down.right.and.arrow.up.left", action: #selector(fit)))
        options.addArrangedSubview(button("100%", symbol: nil, action: #selector(actualSize)))
        options.addArrangedSubview(button("−", symbol: nil, action: #selector(zoomOut)))
        options.addArrangedSubview(button("+", symbol: nil, action: #selector(zoomIn)))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .underPageBackgroundColor
        scroll.documentView = canvas
        let footer = NSStackView()
        footer.spacing = 8
        let hint = NSTextField(labelWithString: "Shift 约束方向 · V 选择后拖动 · Delete 删除")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        footer.addArrangedSubview(hint)
        footer.addArrangedSubview(NSView())
        footer.addArrangedSubview(button("锚定截图", symbol: "pin", action: #selector(pinImage)))
        footer.addArrangedSubview(button("保存 PNG", symbol: "square.and.arrow.down", action: #selector(saveImage)))
        let copy = button("复制截图", symbol: "doc.on.doc", action: #selector(copyImage))
        copy.keyEquivalent = "c"; copy.keyEquivalentModifierMask = .command
        footer.addArrangedSubview(copy)
        let stack = NSStackView(views: [tools, options, scroll, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)
        ])
        for view in [tools, options, scroll, footer] {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        tools.setContentHuggingPriority(.required, for: .vertical)
        options.setContentHuggingPriority(.required, for: .vertical)
        footer.setContentHuggingPriority(.required, for: .vertical)
        content.layoutSubtreeIfNeeded()
    }
    private func button(_ title: String, symbol: String?, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        if let symbol { b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title); b.imagePosition = .imageLeading }
        b.setAccessibilityLabel(title)
        return b
    }
    func choose(_ tool: MarkTool) {
        canvas.tool = tool
        captureToolbar?.selectTool(tool)
        for (key, button) in toolButtons { button.state = key == tool ? .on : .off }
        updateOptions()
        window?.makeFirstResponder(canvas)
    }
    private func updateOptions() {
        guard !isCapture else { return }
        let tool = canvas.settingsTool
        colorCaption.isHidden = tool.isRedaction
        colorButtons.forEach { $0.isHidden = tool.isRedaction }
        widthSelector.configureStyle(for: canvas)
        redactionModeSelector.isHidden = !tool.isRedaction
        redactionModeSelector.selectedSegment = canvas.redactionMode.rawValue
        brushSizeSelector.isHidden = !tool.isRedaction || canvas.redactionMode != .brush
        brushSizeSelector.configure(title: "笔刷", value: canvas.redactionBrushSize, range: 6...200, step: 1)
    }
    @objc private func toolClicked(_ sender: NSButton) {
        if let id = sender.identifier?.rawValue, let tool = MarkTool(rawValue: id) { choose(tool) }
    }
    @objc private func colorClicked(_ sender: NSButton) {
        canvas.commitText()
        canvas.markColor = [NSColor.systemRed, .systemOrange, .systemBlue, .black, .white][sender.tag]
        colorButtons.forEach { $0.state = $0 === sender ? .on : .off }
        window?.makeFirstResponder(canvas)
    }
    @objc private func redactionModeChanged(_ sender: NSSegmentedControl) {
        canvas.redactionMode = RedactionMode(rawValue: sender.selectedSegment) ?? .region
        brushSizeSelector.isHidden = canvas.redactionMode != .brush
        window?.makeFirstResponder(canvas)
    }
    @objc func undoMark() { canvas.undo(); window?.makeFirstResponder(canvas) }
    @objc func redoMark() { canvas.redo(); window?.makeFirstResponder(canvas) }
    @objc func deleteMark() { canvas.deleteSelected() }
    @objc private func fit() {
        window?.contentView?.layoutSubtreeIfNeeded()
        let area = scroll.contentSize
        setZoom(min(1, min((area.width - 16) / canvas.logicalSize.width, (area.height - 16) / canvas.logicalSize.height)))
    }
    @objc private func actualSize() { setZoom(1) }
    @objc private func zoomIn() { setZoom(zoom * 1.25) }
    @objc private func zoomOut() { setZoom(zoom / 1.25) }
    private func setZoom(_ value: CGFloat) {
        canvas.commitText()
        zoom = max(0.02, min(4, value))
        canvas.setFrameSize(CGSize(width: canvas.logicalSize.width * zoom, height: canvas.logicalSize.height * zoom))
        canvas.needsDisplay = true
    }
    @objc func copyImage() {
        guard let image = canvas.renderedImage(), let png = Renderer.png(image) else { showError("无法生成截图"); return }
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setData(png, forType: .png) {
            if isCapture { close() } else { window?.title = "轻截 · 已复制截图" }
        } else { showError("无法写入剪贴板，请重试") }
    }
    @objc func pinImage() {
        guard let onPin else { return }
        guard let image = canvas.renderedImage(), let window else { showError("无法生成截图"); return }
        let frame = window.convertToScreen(canvas.convert(canvas.bounds, to: nil))
        onPin(image, canvas.logicalSize, frame)
        if isCapture { close() }
    }
    @objc func saveImage() {
        canvas.commitText()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "轻截-\(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-"))"
        guard let window else { return }
        if isCapture { window.level = .normal }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            if self.isCapture { self.window?.level = .screenSaver }
            guard response == .OK, let url = panel.url else { self.window?.makeFirstResponder(self.canvas); return }
            do {
                guard let image = self.canvas.renderedImage(), let data = Renderer.png(image) else { throw ExportError.failed }
                try data.write(to: url, options: .atomic)
                if self.isCapture { self.close() } else { self.window?.title = "轻截 · 已保存截图" }
            } catch { self.showError("保存失败：\(error.localizedDescription)") }
        }
    }
    private func showError(_ message: String) {
        let alert = NSAlert(); alert.messageText = message
        if let window {
            if isCapture { window.level = .normal }
            alert.beginSheetModal(for: window) { [weak self] _ in
                if self?.isCapture == true { self?.window?.level = .screenSaver }
                self?.window?.makeFirstResponder(self?.canvas)
            }
        }
    }
    func windowWillClose(_ notification: Notification) { onClose?() }
    private enum ExportError: LocalizedError {
        case failed
        var errorDescription: String? { "无法编码 PNG" }
    }
}

private final class EditorBackgroundView: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }
}
