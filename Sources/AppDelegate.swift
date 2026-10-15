import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var shortcut: HotKey?
    private var textShortcut: HotKey?
    private var textCaptureShortcut = CaptureShortcut.load(key: CaptureShortcut.textStorageKey, fallback: .textDefaultValue)
    private var textCaptureItem: NSMenuItem!
    private var pinnedVisibilityItem: NSMenuItem!
    private var isTextCapture = false
    private let textCapture = TextCaptureController()
    private let screenshotHistory = ScreenshotHistory()
    private var historyWindow: HistoryWindowController?
    private var captureShortcut = CaptureShortcut.load()
    private var captureItem: NSMenuItem!
    private var shortcutSettings: ShortcutSettingsController?
    private let capture = CaptureCoordinator()
    private var editors: [EditorController] = []
    private let pinnedScreenshots = PinnedScreenshotManager()
    private var loginItem: NSMenuItem!
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let existing = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            existing.activate(options: []); NSApp.terminate(nil); return
        }
        createMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "轻截 MacMark")
        let menu = NSMenu()
        menu.delegate = self
        captureItem = add("区域截图", action: #selector(takeScreenshot), to: menu)
        add("截图快捷键…", action: #selector(configureShortcut), to: menu)
        textCaptureItem = add("提取文字", action: #selector(takeTextScreenshot), to: menu)
        add("文字提取快捷键…", action: #selector(configureTextShortcut), to: menu)
        add("最近截图…", action: #selector(showHistory), to: menu)
        pinnedVisibilityItem = add("隐藏全部贴图", action: #selector(togglePinnedVisibility), to: menu)
        updateShortcutDisplay()
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
        capture.onCapture = { [weak self] image, size, context in
            guard let self else { return }
            if self.isTextCapture {
                context.window.orderOut(nil); context.window.close(); self.capture.cancel()
                self.textCapture.recognize(image)
            } else { self.showEditor(image, size: size, captureContext: context) }
        }
        capture.onError = { [weak self] message in self?.alert(message) }
        capture.prepare()
        shortcut = HotKey { [weak self] in self?.takeScreenshot() }
        if shortcut?.register(captureShortcut) != true { showShortcutError() }
        textShortcut = HotKey { [weak self] in self?.takeTextScreenshot() }
        if textShortcut?.register(textCaptureShortcut) != true { alert("文字提取快捷键注册失败，请在菜单栏更换快捷键。") }
        if !UserDefaults.standard.bool(forKey: "didShowWelcome") {
            UserDefaults.standard.set(true, forKey: "didShowWelcome")
            showHelp()
        }
    }
    private func createMainMenu() {
        let root = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "轻截")
        add("截图快捷键…", action: #selector(configureShortcut), to: appMenu)
        add("文字提取快捷键…", action: #selector(configureTextShortcut), to: appMenu)
        add("退出轻截", action: #selector(quit), to: appMenu, key: "q")
        appItem.submenu = appMenu; root.addItem(appItem)
        let fileItem = NSMenuItem(title: "文件", action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: "文件")
        add("打开图片…", action: #selector(openImage), to: fileMenu, key: "o")
        add("保存 PNG…", action: #selector(saveCurrent), to: fileMenu, key: "s")
        add("关闭窗口", action: #selector(closeCurrent), to: fileMenu, key: "w")
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
    @objc private func takeScreenshot() { startCapture(textOnly: false) }
    @objc private func takeTextScreenshot() { startCapture(textOnly: true) }
    private func startCapture(textOnly: Bool) {
        if let shortcutSettings { shortcutSettings.window?.makeKeyAndOrderFront(nil); return }
        guard !capture.busy else { return }
        textCapture.cancel(); isTextCapture = textOnly
        capture.start()
    }
    private func updateShortcutDisplay() {
        statusItem.button?.toolTip = "轻截 · \(captureShortcut.display) 截图"
        captureItem.keyEquivalent = captureShortcut.keyEquivalent
        captureItem.keyEquivalentModifierMask = captureShortcut.modifiers
        textCaptureItem.keyEquivalent = textCaptureShortcut.keyEquivalent
        textCaptureItem.keyEquivalentModifierMask = textCaptureShortcut.modifiers
    }
    private func showShortcutError() {
        alert("\(captureShortcut.display) 快捷键注册失败，可能被其他应用占用。可在菜单栏「截图快捷键…」中更换，或使用「区域截图」。")
    }
    @objc private func configureShortcut() { showShortcutSettings(textOnly: false) }
    @objc private func configureTextShortcut() { showShortcutSettings(textOnly: true) }
    private func showShortcutSettings(textOnly: Bool) {
        if let shortcutSettings {
            shortcutSettings.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        // The old global shortcut must be released so its keys can be recorded too.
        shortcut?.unregister(); textShortcut?.unregister()
        let settings = ShortcutSettingsController(shortcut: textOnly ? textCaptureShortcut : captureShortcut,
            purpose: textOnly ? "提取文字" : "区域截图", defaultShortcut: textOnly ? .textDefaultValue : .defaultValue)
        shortcutSettings = settings
        settings.onApply = { [weak self] value in
            guard let self else { return "无法保存快捷键，请重新打开设置。" }
            if let title = value.conflictingMenuTitle(in: NSApp.mainMenu) {
                return "该组合键已用于「\(title)」，请选择其他组合。"
            }
            let other = textOnly ? self.captureShortcut : self.textCaptureShortcut
            guard value.keyCode != other.keyCode || value.modifiers != other.modifiers else { return "截图与文字提取不能使用相同快捷键。" }
            let hotKey = textOnly ? self.textShortcut : self.shortcut
            guard hotKey?.register(value) == true else { return "快捷键被占用或无法注册，请选择其他组合。" }
            if textOnly { self.textCaptureShortcut = value } else { self.captureShortcut = value }
            value.save(key: textOnly ? CaptureShortcut.textStorageKey : CaptureShortcut.storageKey)
            self.updateShortcutDisplay()
            return nil
        }
        settings.onClose = { [weak self] in
            guard let self else { return }
            self.shortcutSettings = nil
            if self.shortcut?.register(self.captureShortcut) != true { self.showShortcutError() }
            if self.textShortcut?.register(self.textCaptureShortcut) != true { self.alert("文字提取快捷键注册失败，请更换快捷键。") }
        }
    }
    @objc private func saveCurrent() {
        if let pinned = NSApp.keyWindow?.windowController as? PinnedScreenshotController { pinned.saveScreenshot(nil) }
        else if let history = NSApp.keyWindow?.windowController as? HistoryWindowController { history.saveSelected() }
        else { current?.saveImage() }
    }
    @objc private func closeCurrent() { NSApp.keyWindow?.windowController?.close() }
    @objc private func copyCurrent() {
        if let pinned = NSApp.keyWindow?.windowController as? PinnedScreenshotController { pinned.copySelectedText() }
        else if NSApp.keyWindow?.firstResponder is NSTextView { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) }
        else if let history = NSApp.keyWindow?.windowController as? HistoryWindowController { history.copySelected() }
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
    private func showEditor(_ image: CGImage, size: CGSize, captureContext: CaptureEditingContext? = nil) {
        let editor = EditorController(image: image, size: size, captureContext: captureContext)
        editors.append(editor)
        editor.onPin = { [weak self] image, size, frame in
            self?.pinnedScreenshots.pin(image: image, size: size, preferredFrame: frame)
        }
        editor.onExport = { [weak self] image, png in
            do { try self?.screenshotHistory.add(image, png: png) }
            catch {
                DispatchQueue.main.async { [weak self] in self?.alert("截图已完成，但记录历史失败：\(error.localizedDescription)") }
            }
        }
        editor.onClose = { [weak self, weak editor] in
            self?.editors.removeAll { $0 === editor }
            if captureContext != nil { self?.capture.cancel() }
        }
    }
    @objc private func showHistory() {
        if historyWindow == nil {
            let controller = HistoryWindowController(history: screenshotHistory)
            controller.onOpen = { [weak self] image in
                self?.showEditor(image, size: CGSize(width: image.width, height: image.height))
            }
            historyWindow = controller
        }
        historyWindow?.present()
    }
    @objc private func togglePinnedVisibility() { pinnedScreenshots.toggleVisibility() }
    func menuNeedsUpdate(_ menu: NSMenu) {
        pinnedVisibilityItem.title = pinnedScreenshots.isHidden ? "恢复全部贴图" : "隐藏全部贴图"
        pinnedVisibilityItem.isEnabled = !pinnedScreenshots.screenshots.isEmpty
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
        alert("轻截已在菜单栏待命。按 \(captureShortcut.display) 或点击菜单栏「区域截图」，拖动框选，松开后直接在原位置标注，工具栏显示在选区旁，可拖动空白处移动。Esc 或右键取消。菜单栏「截图快捷键…」可自定义组合键。\n\n工具：A 箭头、L 直线、P 画笔、R 方框、T 文字、N 序号、V 选择。按住 Shift 画横线、竖线或正方形。选择后可拖动标注，Delete 删除，⌘Z 撤销。\n\n⌘C 复制，⌘S 保存 PNG；成功后结束本次截图。打开本地图片仍使用独立编辑器。按 \(textCaptureShortcut.display) 框选后直接复制文字。贴图右键可缩放、调整不透明度、复制和保存；菜单栏可隐藏或恢复全部贴图。\n\n「最近截图」默认在本机保留最近 20 张已复制、保存或锚定的图片，可关闭记录或清空。图片只在本地处理。首次截图需要屏幕录制权限。")
    }
    private func alert(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(); alert.messageText = "轻截 MacMark"; alert.informativeText = message
        alert.addButton(withTitle: "知道了"); alert.runModal()
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
