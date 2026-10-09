import AppKit
import VisionKit

final class PinnedScreenshotManager {
    private(set) var screenshots: [PinnedScreenshotController] = []
    @discardableResult func pin(image: CGImage, size: CGSize, preferredFrame: CGRect) -> PinnedScreenshotController {
        let center = CGPoint(x: preferredFrame.midX, y: preferredFrame.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        let frame = Self.placement(size: size, preferredFrame: preferredFrame, within: bounds)
        let screenshot = PinnedScreenshotController(image: image, frame: frame)
        screenshots.append(screenshot)
        screenshot.onClose = { [weak self, weak screenshot] in
            self?.screenshots.removeAll { $0 === screenshot }
        }
        screenshot.window?.orderFrontRegardless()
        return screenshot
    }
    static func placement(size: CGSize, preferredFrame: CGRect, within bounds: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
        let scale = min(1, min(bounds.width / size.width, bounds.height / size.height))
        let width = size.width * scale, height = size.height * scale
        return CGRect(x: max(bounds.minX, min(preferredFrame.minX, bounds.maxX - width)),
                      y: max(bounds.minY, min(preferredFrame.maxY - height, bounds.maxY - height)), width: width, height: height)
    }
}

final class PinnedScreenshotController: NSWindowController, NSWindowDelegate {
    let image: CGImage
    var onClose: (() -> Void)?
    init(image: CGImage, frame: CGRect, recognizer: PinnedTextRecognizing? = nil) {
        self.image = image
        let panel = PinnedScreenshotWindow(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "轻截 · 锚定截图"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        super.init(window: panel)
        panel.delegate = self
        let view = PinnedScreenshotView(image: image, recognizer: recognizer ?? PinnedTextRecognizer())
        view.onDestroy = { [weak self] in self?.close() }
        panel.contentView = view
        view.startRecognition()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func copySelectedText() { (window?.contentView as? PinnedScreenshotView)?.copySelectedText(nil) }
    func windowWillClose(_ notification: Notification) {
        (window?.contentView as? PinnedScreenshotView)?.stopRecognition()
        onClose?()
    }
}

final class PinnedScreenshotWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "c",
           let view = contentView as? PinnedScreenshotView, !view.selectedText.isEmpty {
            view.copySelectedText(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

final class PinnedScreenshotView: NSView, ImageAnalysisOverlayViewDelegate, NSMenuItemValidation {
    enum RecognitionState { case recognizing, ready, empty, failed, stopped }
    private let source: CGImage
    private let imageView = NSImageView()
    let textOverlay = ImageAnalysisOverlayView(frame: .zero)
    private let recognizer: PinnedTextRecognizing
    private var recognitionTask: Task<Void, Never>?
    private(set) var recognizedText = ""
    private(set) var recognitionState = RecognitionState.recognizing
    var selectedText: String { textOverlay.selectedText }
    private var dragOffset: CGPoint?
    var onDestroy: (() -> Void)?
    override var isFlipped: Bool { true }
    init(image: CGImage, recognizer: PinnedTextRecognizing) {
        source = image
        self.recognizer = recognizer
        super.init(frame: .zero)
        imageView.image = NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))
        imageView.imageScaling = .scaleAxesIndependently
        imageView.imageFrameStyle = .none
        imageView.frame = bounds
        imageView.autoresizingMask = [.width, .height]
        addSubview(imageView)
        textOverlay.delegate = self
        textOverlay.trackingImageView = imageView
        textOverlay.preferredInteractionTypes = .textSelection
        textOverlay.isSupplementaryInterfaceHidden = true
        textOverlay.frame = bounds
        textOverlay.autoresizingMask = [.width, .height]
        addSubview(textOverlay)
        setAccessibilityLabel("锚定截图，选中文字后复制，拖动空白处移动，右键复制全部文字或销毁")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    func startRecognition() {
        recognitionTask?.cancel()
        recognitionState = .recognizing
        let image = source, recognizer = recognizer
        recognitionTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled else { return }
            do {
                let result = try await recognizer.recognize(image)
                guard !Task.isCancelled, let self else { return }
                self.recognizedText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                self.textOverlay.analysis = result.analysis
                self.recognitionState = self.recognizedText.isEmpty ? .empty : .ready
                self.window?.invalidateCursorRects(for: self)
            } catch {
                guard !Task.isCancelled else { return }
                self?.recognitionState = .failed
            }
        }
    }
    func stopRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionState = .stopped
        textOverlay.analysis = nil
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        // VisionKit's text probes use the displayed image's top-left coordinates.
        if textOverlay.hasInteractiveItem(at: local) {
            return textOverlay.hitTest(local) ?? textOverlay
        }
        return self
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        window?.invalidateShadow()
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { super.mouseDown(with: event); return }
        textOverlay.resetSelection()
        dragOffset = event.locationInWindow
        NSCursor.closedHand.set()
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window, let offset = dragOffset else { return }
        let point = window.convertPoint(toScreen: event.locationInWindow)
        window.setFrameOrigin(CGPoint(x: point.x - offset.x, y: point.y - offset.y))
        NSCursor.closedHand.set()
    }
    override func mouseUp(with event: NSEvent) { dragOffset = nil; NSCursor.openHand.set() }
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu(title: "锚定截图")
        menu.autoenablesItems = false
        if !selectedText.isEmpty {
            let copy = NSMenuItem(title: "复制选中文字", action: #selector(copySelectedText(_:)), keyEquivalent: "c")
            copy.target = self
            menu.addItem(copy)
        }
        appendScreenshotActions(to: menu)
        return menu
    }
    private func appendScreenshotActions(to menu: NSMenu) {
        let copyAll = NSMenuItem(title: "复制全部文字", action: #selector(copyAllText(_:)), keyEquivalent: "")
        copyAll.target = self
        copyAll.isEnabled = !recognizedText.isEmpty
        menu.addItem(copyAll)
        let status: String?
        switch recognitionState {
        case .recognizing: status = "正在识别文字…"
        case .empty: status = "未识别到文字"
        case .failed: status = "文字识别失败"
        default: status = nil
        }
        if let status {
            let item = NSMenuItem(title: status, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        if recognitionState == .failed {
            let retry = NSMenuItem(title: "重新识别文字", action: #selector(retryRecognition), keyEquivalent: "")
            retry.target = self
            menu.addItem(retry)
        }
        menu.addItem(.separator())
        let destroy = NSMenuItem(title: "销毁锚定截图", action: #selector(destroyScreenshot), keyEquivalent: "")
        destroy.target = self
        menu.addItem(destroy)
    }
    @objc func copySelectedText(_ sender: Any?) { copyText(selectedText) }
    @objc func copyAllText(_ sender: Any?) { copyText(recognizedText) }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(copyAllText(_:)): return !recognizedText.isEmpty
        case #selector(copySelectedText(_:)): return !selectedText.isEmpty
        default: return true
        }
    }
    private func copyText(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    @objc private func retryRecognition() { startRecognition() }
    func overlayView(_ overlayView: ImageAnalysisOverlayView, shouldBeginAt point: CGPoint,
                     forAnalysisType analysisType: ImageAnalysisOverlayView.InteractionTypes) -> Bool {
        window?.makeKey()
        window?.makeFirstResponder(overlayView)
        return true
    }
    func overlayView(_ overlayView: ImageAnalysisOverlayView, updatedMenuFor menu: NSMenu,
                     for event: NSEvent, at point: CGPoint) -> NSMenu {
        menu.addItem(.separator())
        appendScreenshotActions(to: menu)
        return menu
    }
    func textSelectionDidChange(_ overlayView: ImageAnalysisOverlayView) {
        if overlayView.hasActiveTextSelection { window?.makeKey() }
    }
    @objc private func destroyScreenshot() { onDestroy?() }
}
