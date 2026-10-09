import AppKit
import ScreenCaptureKit

@MainActor
final class CaptureCoordinator {
    private var overlays: [NSWindow] = []
    private var busy = false
    private var previousApp: NSRunningApplication?
    var onCapture: ((CGImage, CGSize) -> Void)?
    var onError: ((String) -> Void)?
    func start() {
        guard !busy else { return }
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            onError?("请在系统设置 → 隐私与安全性 → 屏幕与系统音频录制中允许轻截，然后退出并重新打开应用。")
            return
        }
        busy = true
        previousApp = NSWorkspace.shared.frontmostApplication
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                // Freeze all displays before presenting overlays; never capture our selection UI.
                var captures: [(NSScreen, CGImage)] = []
                for screen in NSScreen.screens {
                    guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                          let display = content.displays.first(where: { $0.displayID == number.uint32Value }) else { continue }
                    let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
                    let config = SCStreamConfiguration()
                    config.width = Int(screen.frame.width * screen.backingScaleFactor)
                    config.height = Int(screen.frame.height * screen.backingScaleFactor)
                    config.showsCursor = false
                    config.captureResolution = .best
                    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                    captures.append((screen, image))
                }
                guard !captures.isEmpty else { throw CaptureError.noDisplay }
                present(captures)
            } catch {
                finish()
                onError?("截图失败：\(error.localizedDescription)")
            }
        }
    }
    private func present(_ captures: [(NSScreen, CGImage)]) {
        NSApp.activate(ignoringOtherApps: true)
        for (screen, image) in captures {
            let window = SelectionWindow(contentRect: screen.frame, styleMask: .borderless,
                                         backing: .buffered, defer: false)
            window.level = .screenSaver
            window.isOpaque = true
            window.backgroundColor = .black
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isReleasedWhenClosed = false
            let view = SelectionView(image: image, size: screen.frame.size)
            view.onCancel = { [weak self] in self?.cancel() }
            view.onSelect = { [weak self] rect in
                let pixels = Geometry.cropRect(selection: rect, screenSize: screen.frame.size,
                                               imageSize: CGSize(width: image.width, height: image.height))
                guard pixels.width >= 2, pixels.height >= 2, let cropped = image.cropping(to: pixels) else { return }
                let size = CGSize(width: pixels.width * screen.frame.width / CGFloat(image.width),
                                  height: pixels.height * screen.frame.height / CGFloat(image.height))
                self?.finish()
                self?.onCapture?(cropped, size)
            }
            window.contentView = view
            overlays.append(window)
            window.orderFrontRegardless()
            if screen.frame.contains(NSEvent.mouseLocation) { window.makeKey(); window.makeFirstResponder(view) }
        }
    }
    func cancel() {
        finish()
        previousApp?.activate(options: [])
    }
    private func finish() {
        for window in overlays { window.orderOut(nil); window.close() }
        overlays.removeAll()
        busy = false
    }
    private enum CaptureError: LocalizedError {
        case noDisplay
        var errorDescription: String? { "没有可截图的显示器" }
    }
}

final class SelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}
