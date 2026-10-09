import AppKit

final class ShortcutSettingsController: NSWindowController, NSWindowDelegate {
    let recorder: ShortcutRecorder
    private let message = NSTextField(wrappingLabelWithString: "组合键需包含 ⌘、⌥ 或 ⌃；也可单独使用 F1–F20。")
    private var eventMonitor: Any?
    var onApply: ((CaptureShortcut) -> String?)?
    var onClose: (() -> Void)?
    init(shortcut: CaptureShortcut) {
        recorder = ShortcutRecorder(shortcut: shortcut)
        let window = ShortcutSettingsWindow(contentRect: CGRect(x: 0, y: 0, width: 460, height: 240),
                                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "截图快捷键"
        window.isReleasedWhenClosed = false
        window.contentView = ShortcutSettingsBackgroundView()
        super.init(window: window)
        window.delegate = self
        window.recorder = recorder
        buildUI()
        recorder.onMessage = { [weak self] text, error in
            self?.message.stringValue = text
            self?.message.textColor = error ? .systemRed : .secondaryLabelColor
        }
        // Consume recorded combinations before they reach menu commands such as ⌘Q or ⌘S.
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, event.window === self.window, self.recorder.isRecording else { return event }
            if event.type == .flagsChanged { self.recorder.updateModifiers(event.modifierFlags); return event }
            self.recorder.record(event)
            return nil
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(recorder)
        NSApp.activate(ignoringOtherApps: true)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func buildUI() {
        guard let content = window?.contentView else { return }
        let title = NSTextField(labelWithString: "设置触发区域截图的快捷键")
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        let hint = NSTextField(labelWithString: "点击下方按钮，再按下新的组合键。")
        hint.textColor = .secondaryLabelColor
        message.font = .systemFont(ofSize: 12)
        message.textColor = .secondaryLabelColor
        let actions = NSStackView()
        actions.spacing = 8
        let reset = NSButton(title: "恢复默认", target: self, action: #selector(resetShortcut))
        reset.bezelStyle = .rounded
        actions.addArrangedSubview(reset)
        actions.addArrangedSubview(NSView())
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancelSettings))
        cancel.bezelStyle = .rounded; cancel.keyEquivalent = "\u{1b}"
        actions.addArrangedSubview(cancel)
        let save = NSButton(title: "保存", target: self, action: #selector(applyShortcut))
        save.bezelStyle = .rounded; save.keyEquivalent = "\r"
        actions.addArrangedSubview(save)
        let stack = NSStackView(views: [title, hint, recorder, message, actions])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            recorder.widthAnchor.constraint(equalTo: stack.widthAnchor),
            recorder.heightAnchor.constraint(equalToConstant: 40),
            message.widthAnchor.constraint(equalTo: stack.widthAnchor),
            actions.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        content.layoutSubtreeIfNeeded()
    }
    @objc private func resetShortcut() {
        recorder.setShortcut(.defaultValue)
        message.stringValue = "已选择默认快捷键，点击保存后生效。"
        message.textColor = .secondaryLabelColor
    }
    @objc private func cancelSettings() { close() }
    @objc private func applyShortcut() {
        guard !recorder.isRecording else {
            message.stringValue = "请先按下完整组合键，或按 Esc 取消录入。"
            message.textColor = .systemRed
            return
        }
        guard let onApply else { return }
        if let error = onApply(recorder.shortcut) {
            message.stringValue = error; message.textColor = .systemRed
        } else { close() }
    }
    private func removeMonitor() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
    }
    func windowWillClose(_ notification: Notification) { removeMonitor(); onClose?() }
    deinit { removeMonitor() }
}

final class ShortcutRecorder: NSButton {
    private(set) var shortcut: CaptureShortcut
    private(set) var isRecording = false
    var onMessage: ((String, Bool) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    init(shortcut: CaptureShortcut) {
        self.shortcut = shortcut
        super.init(frame: .zero)
        bezelStyle = .rounded
        font = .systemFont(ofSize: 18, weight: .medium)
        target = self; action = #selector(beginRecording)
        setShortcut(shortcut)
        setAccessibilityLabel("截图快捷键，点击后按下新的组合键")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func setShortcut(_ value: CaptureShortcut) {
        shortcut = value; isRecording = false
        title = "\(value.display)  ·  点击修改"
        setAccessibilityValue(value.display)
    }
    @objc func beginRecording() {
        isRecording = true; title = "请按下快捷键…"
        window?.makeFirstResponder(self)
        onMessage?("按 Esc 可取消本次录入。", false)
    }
    func updateModifiers(_ flags: NSEvent.ModifierFlags) {
        let symbols = CaptureShortcut.modifierSymbols(flags)
        title = symbols.isEmpty ? "请按下快捷键…" : symbols + "…"
    }
    func record(_ event: NSEvent) {
        if event.keyCode == 53 {
            setShortcut(shortcut)
            onMessage?("已取消录入，快捷键保持原值。", false)
        } else if let value = CaptureShortcut(event: event) {
            setShortcut(value)
            onMessage?("点击保存后生效。", false)
        } else {
            onMessage?("请使用包含 ⌘、⌥ 或 ⌃ 的组合键，或 F1–F20。", true)
        }
    }
    override func keyDown(with event: NSEvent) {
        if isRecording { record(event) } else { super.keyDown(with: event) }
    }
}

private final class ShortcutSettingsWindow: NSWindow {
    weak var recorder: ShortcutRecorder?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let recorder, recorder.isRecording { recorder.record(event); return true }
        return super.performKeyEquivalent(with: event)
    }
}

private final class ShortcutSettingsBackgroundView: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }
}
