import AppKit

@MainActor
final class CaptureCoordinator {
    private(set) var overlays: [NSWindow] = []
    private(set) var busy = false
    private var previousApp: NSRunningApplication?
    private let source: CaptureImageSource
    private let hasAccess: () -> Bool
    private let displays: @MainActor () -> [CaptureDisplay]
    private var session: UUID?
    private var captureTask: Task<Void, Never>?
    private var snapshots: [CGDirectDisplayID: CGImage] = [:]
    private var windows: [CGDirectDisplayID: NSWindow] = [:]
    var onCapture: ((CGImage, CGSize, CaptureEditingContext) -> Void)?
    var onError: ((String) -> Void)?
    init(source: CaptureImageSource? = nil,
         hasAccess: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() },
         displays: (@MainActor () -> [CaptureDisplay])? = nil) {
        self.source = source ?? ScreenSnapshotSource(); self.hasAccess = hasAccess
        self.displays = displays ?? CaptureDisplay.current
    }
    func prepare() { if hasAccess() { source.prepare() } }
    func start() {
        guard !busy else { return }
        guard hasAccess() else {
            CGRequestScreenCaptureAccess()
            onError?("请在系统设置 → 隐私与安全性 → 屏幕与系统音频录制中允许轻截，然后退出并重新打开应用。")
            return
        }
        let targets = displays()
        guard !targets.isEmpty else { onError?("没有可截图的显示器"); return }
        busy = true
        previousApp = NSWorkspace.shared.frontmostApplication
        let id = UUID(); session = id
        present(targets, session: id)
        captureTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await source.capture(targets) { [weak self] target, image in
                    guard let self, self.session == id, let window = self.windows[target.id],
                          let view = window.contentView as? SelectionView else { return }
                    self.snapshots[target.id] = image
                    window.isOpaque = true; window.backgroundColor = .black
                    view.updateSnapshot(image)
                }
            } catch {
                guard self.session == id, !Task.isCancelled else { return }
                self.finish()
                self.onError?("截图失败：\(error.localizedDescription)")
            }
        }
    }
    private func present(_ targets: [CaptureDisplay], session id: UUID) {
        let keyDisplay = targets.first { $0.frame.contains(NSEvent.mouseLocation) } ?? targets.first
        for target in targets {
            let window = SelectionWindow(contentRect: target.frame, styleMask: [.borderless, .nonactivatingPanel],
                                         backing: .buffered, defer: false)
            window.level = .screenSaver
            window.isOpaque = false; window.backgroundColor = .clear
            window.hidesOnDeactivate = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isReleasedWhenClosed = false
            let view = SelectionView(size: target.frame.size, pixelSize: target.pixelSize)
            view.onCancel = { [weak self] in self?.cancel() }
            view.onSelect = { [weak self, weak window] rect in
                guard let self, self.session == id, let window, let image = self.snapshots[target.id],
                      let onCapture = self.onCapture else { return }
                let pixels = Geometry.cropRect(selection: rect, screenSize: target.frame.size,
                                               imageSize: CGSize(width: image.width, height: image.height))
                guard pixels.width >= 2, pixels.height >= 2, let cropped = image.cropping(to: pixels) else { return }
                self.session = nil
                self.captureTask?.cancel(); self.captureTask = nil
                self.overlays.removeAll { $0 === window }
                for overlay in self.overlays { overlay.orderOut(nil); overlay.close() }
                self.overlays.removeAll(); self.windows.removeAll(); self.snapshots.removeAll()
                onCapture(cropped, rect.size, CaptureEditingContext(window: window, snapshot: image, selection: rect))
            }
            window.contentView = view
            overlays.append(window); windows[target.id] = window
            window.orderFrontRegardless()
            if target.id == keyDisplay?.id { window.makeKey(); window.makeFirstResponder(view) }
        }
    }
    func cancel() {
        finish()
        previousApp?.activate(options: [])
        previousApp = nil
    }
    private func finish() {
        session = nil
        captureTask?.cancel(); captureTask = nil
        for window in overlays { window.orderOut(nil); window.close() }
        overlays.removeAll(); windows.removeAll(); snapshots.removeAll()
        busy = false
    }
}

final class SelectionWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
