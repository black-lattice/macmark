import AppKit
import ScreenCaptureKit

struct CaptureDisplay: Sendable {
    let id: CGDirectDisplayID
    let frame: CGRect
    let pixelSize: CGSize
    @MainActor static func current() -> [CaptureDisplay] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return CaptureDisplay(id: number.uint32Value, frame: screen.frame,
                                  pixelSize: CGSize(width: screen.frame.width * screen.backingScaleFactor,
                                                    height: screen.frame.height * screen.backingScaleFactor))
        }
    }
}

@MainActor protocol CaptureImageSource {
    func prepare()
    func capture(_ displays: [CaptureDisplay], receive: @escaping (CaptureDisplay, CGImage) -> Void) async throws
}

@MainActor final class ScreenSnapshotSource: CaptureImageSource {
    private struct Content {
        let displays: [SCDisplay]
        let ownApps: [SCRunningApplication]
        let windows: [SCWindow]
    }
    private var cached: Content?
    private var preparing: Task<Content, Error>?
    private var generation = 0
    private var observer: NSObjectProtocol?
    init() {
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.invalidate() }
        }
    }
    func prepare() { Task { [weak self] in _ = try? await self?.content() } }
    private func invalidate() {
        generation += 1
        cached = nil
        preparing?.cancel(); preparing = nil
    }
    private func content() async throws -> Content {
        if let cached { return cached }
        let current = generation
        let task: Task<Content, Error>
        if let preparing { task = preparing }
        else {
            task = Task {
                let shared = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                try Task.checkCancellation()
                return Content(displays: shared.displays,
                               ownApps: shared.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier },
                               windows: shared.windows)
            }
            preparing = task
        }
        do {
            let value = try await task.value
            if current == generation {
                preparing = nil
                // Without an application entry, a later overlay cannot safely be excluded.
                if !value.ownApps.isEmpty { cached = value }
            }
            return value
        } catch {
            if current == generation { preparing = nil }
            throw error
        }
    }
    static func pinnedWindowIDs() -> Set<CGWindowID> {
        Set(NSApp.windows.compactMap { window in
            guard window is PinnedScreenshotWindow, window.isVisible else { return nil }
            return CGWindowID(window.windowNumber)
        })
    }
    func capture(_ displays: [CaptureDisplay], receive: @escaping (CaptureDisplay, CGImage) -> Void) async throws {
        var available = try await content()
        let pinnedIDs = Self.pinnedWindowIDs()
        if available.ownApps.isEmpty || !displays.allSatisfy({ target in available.displays.contains { $0.displayID == target.id } })
            || !pinnedIDs.isSubset(of: Set(available.windows.map(\.windowID))) {
            invalidate()
            available = try await content()
        }
        try Task.checkCancellation()
        guard !available.ownApps.isEmpty else { throw CaptureFailure.applicationUnavailable }
        let apps = available.ownApps
        let visiblePinnedIDs = Self.pinnedWindowIDs()
        let pinnedWindows = available.windows.filter { visiblePinnedIDs.contains($0.windowID) }
        try await withThrowingTaskGroup(of: (CaptureDisplay, CGImage).self) { group in
            for target in displays {
                guard let display = available.displays.first(where: { $0.displayID == target.id }) else { throw CaptureFailure.noDisplay }
                group.addTask {
                    let filter = SCContentFilter(display: display, excludingApplications: apps, exceptingWindows: pinnedWindows)
                    let config = SCStreamConfiguration()
                    config.width = Int(target.pixelSize.width); config.height = Int(target.pixelSize.height)
                    config.showsCursor = false; config.captureResolution = .best
                    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                    try Task.checkCancellation()
                    return (target, image)
                }
            }
            for try await (target, image) in group {
                try Task.checkCancellation()
                receive(target, image)
            }
        }
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    private enum CaptureFailure: LocalizedError {
        case noDisplay, applicationUnavailable
        var errorDescription: String? {
            self == .noDisplay ? "没有可截图的显示器" : "截图内容尚未就绪，请重试"
        }
    }
}
