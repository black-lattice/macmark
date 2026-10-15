import AppKit
import UniformTypeIdentifiers

enum ImageExport {
    @discardableResult static func copy(_ image: CGImage, window: NSWindow?) -> Bool {
        guard let data = Renderer.png(image) else { showError("无法生成 PNG 图片", window: window); return false }
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setData(data, forType: .png) else {
            showError("无法写入剪贴板，请重试", window: window); return false
        }
        return true
    }
    static func save(_ image: CGImage, window: NSWindow?) {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = "轻截-截图.png"
        let level = window.level
        window.level = .normal
        NSApp.activate(ignoringOtherApps: true)
        panel.beginSheetModal(for: window) { response in
            window.level = level
            guard response == .OK, let url = panel.url else { return }
            do {
                guard let data = Renderer.png(image) else { throw CocoaError(.fileWriteUnknown) }
                try data.write(to: url, options: .atomic)
            } catch { showError("保存失败：\(error.localizedDescription)", window: window) }
        }
    }
    static func showError(_ message: String, window: NSWindow?) {
        let alert = NSAlert(); alert.messageText = "轻截 MacMark"; alert.informativeText = message
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }
}
