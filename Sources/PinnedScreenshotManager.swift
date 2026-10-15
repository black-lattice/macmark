import AppKit

final class PinnedScreenshotManager {
    private(set) var isHidden = false
    func toggleVisibility() {
        isHidden.toggle()
        for screenshot in screenshots {
            if isHidden { screenshot.window?.orderOut(nil) }
            else { screenshot.window?.orderFrontRegardless() }
        }
    }
    private(set) var screenshots: [PinnedScreenshotController] = []
    @discardableResult func pin(image: CGImage, size: CGSize, preferredFrame: CGRect) -> PinnedScreenshotController {
        if isHidden { toggleVisibility() }
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
