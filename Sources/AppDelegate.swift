import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var shortcut: HotKey?
    private let capture = CaptureCoordinator()
    private var editors: [EditorController] = []
    private var loginItem: NSMenuItem!
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let existing = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            existing.activate(options: []); NSApp.terminate(nil); return
        }
        createMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "轻截 MacMark")
        statusItem.button?.toolTip = "轻截 · ⌘⇧2 截图"
        let menu = NSMenu()
        add("区域截图", action: #selector(takeScreenshot), to: menu, key: "2", modifiers: [.command, .shift])
        add("打开图片…", action: #selector(openImage), to: menu)
        menu.addItem(.separator())
        loginItem = add("登录时启动", action: #selector(toggleLogin), to: menu)
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        add("屏幕录制权限…", action: #selector(openPermissions), to: menu)
        add("使用说明", action: #selector(showHelp), to: menu)
        add("检查新版本", action: #selector(openReleases), to: menu)
        menu.addItem(.separator())
        add("退出轻截", action: #selector(quit), to: menu, key: "q")
        statusItem.menu = menu
        capture.onCapture = { [weak self] image, size in self?.showEditor(image, size: size) }
        capture.onError = { [weak self] message in self?.alert(message) }
        shortcut = HotKey { [weak self] in self?.takeScreenshot() }
        if shortcut?.register() != true { alert("⌘⇧2 快捷键注册失败，可能被其他应用占用。仍可通过菜单栏的「区域截图」使用。") }
        if !UserDefaults.standard.bool(forKey: "didShowWelcome") {
            UserDefaults.standard.set(true, forKey: "didShowWelcome")
            showHelp()
        }
    }
    private func createMainMenu() {
        let root = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "轻截")
        add("退出轻截", action: #selector(quit), to: appMenu, key: "q")
        appItem.submenu = appMenu; root.addItem(appItem)
        let fileItem = NSMenuItem(title: "文件", action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: "文件")
        add("打开图片…", action: #selector(openImage), to: fileMenu, key: "o")
        add("保存 PNG…", action: #selector(saveCurrent), to: fileMenu, key: "s")
        fileMenu.addItem(NSMenuItem(title: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        fileItem.submenu = fileMenu; root.addItem(fileItem)
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "编辑")
        add("撤销", action: #selector(undoCurrent), to: editMenu, key: "z")
        add("重做", action: #selector(redoCurrent), to: editMenu, key: "z", modifiers: [.command, .shift])
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        add("复制", action: #selector(copyCurrent), to: editMenu, key: "c")
        editMenu.addItem(NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu; root.addItem(editItem)
        NSApp.mainMenu = root
    }
    @discardableResult private func add(_ title: String, action: Selector, to menu: NSMenu,
                                       key: String = "", modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self; item.keyEquivalentModifierMask = modifiers
        menu.addItem(item)
        return item
    }
    private var current: EditorController? { editors.first { $0.window === NSApp.keyWindow } }
    @objc private func takeScreenshot() { capture.start() }
    @objc private func saveCurrent() { current?.saveImage() }
    @objc private func copyCurrent() {
        if NSApp.keyWindow?.firstResponder is NSTextView { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) }
        else { current?.copyImage() }
    }
    @objc private func undoCurrent() {
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView { text.undoManager?.undo() }
        else { current?.undoMark() }
    }
    @objc private func redoCurrent() {
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView { text.undoManager?.redo() }
        else { current?.redoMark() }
    }
    @objc private func openImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { self?.alert("无法读取这张图片"); return }
            self?.showEditor(image, size: CGSize(width: image.width, height: image.height))
        }
    }
    private func showEditor(_ image: CGImage, size: CGSize) {
        let editor = EditorController(image: image, size: size)
        editors.append(editor)
        editor.onClose = { [weak self, weak editor] in self?.editors.removeAll { $0 === editor } }
    }
    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
            loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
            if SMAppService.mainApp.status == .requiresApproval { alert("请在系统设置 → 通用 → 登录项中允许轻截。") }
        } catch { alert("修改登录启动失败：\(error.localizedDescription)") }
    }
    @objc private func openPermissions() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
    @objc private func openReleases() {
        NSWorkspace.shared.open(URL(string: "https://github.com/black-lattice/macmark/releases/latest")!)
    }
    @objc private func showHelp() {
        alert("轻截已在菜单栏待命。按 ⌘⇧2 或点击菜单栏「区域截图」，拖动框选，Esc 取消。\n\n编辑器：A 箭头、L 直线、P 画笔、R 方框、T 文字、V 选择。按住 Shift 画横线、竖线或正方形。选择后可拖动标注，Delete 删除，⌘Z 撤销。\n\n⌘C 复制，⌘S 保存 PNG。图片只在本地处理。首次截图需要屏幕录制权限。")
    }
    private func alert(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(); alert.messageText = "轻截 MacMark"; alert.informativeText = message
        alert.addButton(withTitle: "知道了"); alert.runModal()
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
