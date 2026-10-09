import AppKit

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
    init(image: CGImage, frame: CGRect) {
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
        let view = PinnedScreenshotView(image: image)
        view.onDestroy = { [weak self] in self?.close() }
        panel.contentView = view
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func windowWillClose(_ notification: Notification) { onClose?() }
}

final class PinnedScreenshotWindow: NSPanel {}

private final class PinnedScreenshotView: NSView {
    private let image: NSImage
    private var dragOffset: CGPoint?
    var onDestroy: (() -> Void)?
    override var isFlipped: Bool { true }
    init(image: CGImage) {
        self.image = NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))
        super.init(frame: .zero)
        setAccessibilityLabel("锚定截图，可拖动移动，右键菜单销毁")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        window?.invalidateShadow()
    }
    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { super.mouseDown(with: event); return }
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
        let destroy = NSMenuItem(title: "销毁锚定截图", action: #selector(destroyScreenshot), keyEquivalent: "")
        destroy.target = self
        menu.addItem(destroy)
        return menu
    }
    @objc private func destroyScreenshot() { onDestroy?() }
}
