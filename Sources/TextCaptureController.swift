import AppKit

@MainActor final class TextCaptureController: NSWindowController, NSWindowDelegate {
    enum State: Equatable { case recognizing, copied, empty, failed, cancelled }
    private(set) var state = State.cancelled
    private let recognizer: PinnedTextRecognizing
    private let message = NSTextField(wrappingLabelWithString: "正在识别文字…")
    private let spinner = NSProgressIndicator()
    private let dismiss = NSButton(title: "取消", target: nil, action: nil)
    private var task: Task<Void, Never>?
    private var session = UUID()
    init(recognizer: PinnedTextRecognizing? = nil) {
        self.recognizer = recognizer ?? PinnedTextRecognizer(useLiveText: false)
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 360, height: 136),
                            styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "轻截 · 提取文字"; panel.isReleasedWhenClosed = false
        panel.level = .floating; panel.hidesOnDeactivate = false
        super.init(window: panel)
        panel.delegate = self
        message.frame = CGRect(x: 24, y: 60, width: 312, height: 52)
        spinner.style = .spinning; spinner.frame = CGRect(x: 24, y: 20, width: 20, height: 20)
        dismiss.frame = CGRect(x: 254, y: 14, width: 82, height: 32)
        dismiss.bezelStyle = .rounded; dismiss.target = self; dismiss.action = #selector(dismissPanel)
        dismiss.keyEquivalent = "\u{1b}"
        [message, spinner, dismiss].forEach { panel.contentView?.addSubview($0) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func recognize(_ image: CGImage) {
        cancel()
        let id = UUID(); session = id
        state = .recognizing; message.stringValue = "正在本地识别文字…"
        dismiss.title = "取消"; spinner.isHidden = false; spinner.startAnimation(nil)
        window?.center(); window?.orderFrontRegardless()
        task = Task { @MainActor [weak self, recognizer] in
            do {
                let result = try await recognizer.recognize(image)
                guard let self, !Task.isCancelled, self.session == id else { return }
                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty { self.finish(.empty, message: "未识别到文字，请重新框选清晰的文字区域。") }
                else {
                    NSPasteboard.general.clearContents()
                    if NSPasteboard.general.setString(text, forType: .string) {
                        self.finish(.copied, message: "已复制 \(text.count) 个字符，可直接粘贴。")
                        try await Task.sleep(nanoseconds: 1_500_000_000)
                        guard !Task.isCancelled, self.session == id else { return }
                        self.window?.orderOut(nil)
                    } else { self.finish(.failed, message: "无法写入剪贴板，请重新提取文字。") }
                }
            } catch {
                guard let self, !Task.isCancelled, self.session == id else { return }
                self.finish(.failed, message: "识别失败：\(error.localizedDescription)\n请重新框选后重试。")
            }
        }
    }
    private func finish(_ state: State, message: String) {
        self.state = state; self.message.stringValue = message
        spinner.stopAnimation(nil); spinner.isHidden = true; dismiss.title = "关闭"
    }
    func cancel() {
        session = UUID(); task?.cancel(); task = nil; state = .cancelled
        spinner.stopAnimation(nil); window?.orderOut(nil)
    }
    @objc private func dismissPanel() { close() }
    func windowWillClose(_ notification: Notification) { cancel() }
}
