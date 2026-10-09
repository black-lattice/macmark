import AppKit
import Carbon

extension Tests {
    @MainActor static func shortcuts() throws {
        let suite = "MacMarkTests.shortcuts.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        expect(CaptureShortcut.load(from: defaults) == .defaultValue, "未设置时使用默认截图快捷键")
        func event(code: Int, flags: NSEvent.ModifierFlags, key: String, window: NSWindow? = nil) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                             windowNumber: window?.windowNumber ?? 0, context: nil, characters: key,
                             charactersIgnoringModifiers: key, isARepeat: false, keyCode: UInt16(code))!
        }
        let custom = CaptureShortcut(event: event(code: kVK_ANSI_S, flags: [.control, .option, .capsLock], key: "s"))!
        expect(custom.modifiers == [.control, .option] && custom.carbonModifiers == UInt32(controlKey | optionKey), "自定义快捷键过滤锁定状态并转换 Carbon 修饰键")
        expect(custom.display == "⌃⌥S", "自定义组合键显示")
        expect(CaptureShortcut(event: event(code: kVK_ANSI_S, flags: [.shift], key: "S")) == nil, "拒绝无主要修饰键的普通按键")
        expect(CaptureShortcut(event: event(code: kVK_Escape, flags: [.command], key: "\u{1b}")) == nil, "Escape 保留为取消键")
        let function = CaptureShortcut(event: event(code: kVK_F18, flags: [.function], key: String(UnicodeScalar(NSF1FunctionKey + 17)!)))!
        expect(function.display == "F18" && function.modifiers.isEmpty, "支持独立功能键")
        custom.save(to: defaults)
        expect(CaptureShortcut.load(from: UserDefaults(suiteName: suite)!) == custom, "快捷键设置可从持久化存储重新读取")
        defaults.set(["keyCode": -1, "modifiers": 0, "keyEquivalent": "s"], forKey: CaptureShortcut.storageKey)
        expect(CaptureShortcut.load(from: defaults) == .defaultValue, "损坏的快捷键设置回退默认值")
        let menu = NSMenu()
        let root = NSMenuItem(); root.submenu = NSMenu()
        root.submenu!.addItem(NSMenuItem(title: "复制", action: nil, keyEquivalent: "c"))
        menu.addItem(root)
        let copy = CaptureShortcut(keyCode: UInt32(kVK_ANSI_C), modifiers: [.command], keyEquivalent: "c")
        expect(copy.conflictingMenuTitle(in: menu) == "复制" && custom.conflictingMenuTitle(in: menu) == nil, "识别与应用菜单冲突的组合键")

        let keys = [kVK_F18, kVK_F19, kVK_F20].enumerated().map { index, code in
            CaptureShortcut(keyCode: UInt32(code), modifiers: CaptureShortcut.modifierMask,
                            keyEquivalent: String(UnicodeScalar(NSF1FunctionKey + 17 + index)!))
        }
        let active = HotKey {}
        let occupied = HotKey {}
        let released = HotKey {}
        defer { active.unregister(); occupied.unregister(); released.unregister() }
        expect(active.register(keys[0]) && occupied.register(keys[1]), "注册不同的真实全局快捷键")
        expect(!active.register(keys[1]) && active.registeredShortcut == keys[0], "注册冲突时保留原快捷键")
        expect(active.register(keys[2]) && released.register(keys[0]), "切换快捷键后释放旧组合")
        expect(active.register(keys[2]), "重复应用当前快捷键不会发生冲突")
        active.unregister()
        expect(active.register(keys[2]), "录入结束后可恢复暂停的快捷键")

        let settings = ShortcutSettingsController(shortcut: .defaultValue)
        var applied: CaptureShortcut?
        var closed = false
        settings.onApply = { value in applied = value; return "测试占用：请选择其他组合。" }
        settings.onClose = { closed = true }
        let recorder = settings.recorder
        recorder.beginRecording()
        expect(settings.window?.firstResponder === recorder && recorder.isRecording, "快捷键录入按钮获得键盘焦点")
        let saveKey = event(code: kVK_ANSI_S, flags: [.command], key: "s", window: settings.window)
        expect(settings.window!.performKeyEquivalent(with: saveKey) && recorder.shortcut.keyEquivalent == "s" && applied == nil,
               "录入组合键时拦截菜单快捷键")
        recorder.beginRecording()
        recorder.record(event(code: kVK_ANSI_S, flags: [], key: "s", window: settings.window))
        expect(recorder.isRecording, "无效录入保持等待状态")
        recorder.record(event(code: kVK_Escape, flags: [], key: "\u{1b}", window: settings.window))
        expect(!recorder.isRecording && recorder.shortcut.keyEquivalent == "s", "Esc 取消录入并保留此前候选值")
        recorder.beginRecording()
        recorder.record(event(code: kVK_ANSI_S, flags: [.control, .option], key: "s", window: settings.window))
        expect(recorder.shortcut == custom, "用户录入自定义快捷键")
        func descendants(_ parent: NSView) -> [NSView] { parent.subviews.flatMap { [$0] + descendants($0) } }
        let buttons = descendants(settings.window!.contentView!).compactMap { $0 as? NSButton }
        buttons.first { $0.title == "保存" }!.performClick(nil)
        expect(applied == custom && !closed && settings.window!.isVisible, "保存失败时保留设置窗口供用户更换组合")
        buttons.first { $0.title == "恢复默认" }!.performClick(nil)
        expect(recorder.shortcut == .defaultValue && applied == custom, "恢复默认需保存后才生效")
        settings.onApply = { value in value.save(to: defaults); return nil }
        let view = settings.window!.contentView!
        view.layoutSubtreeIfNeeded()
        expect(buttons.allSatisfy { $0.bounds.width > 30 && $0.bounds.height > 15 && view.bounds.contains($0.convert($0.bounds, to: view)) }, "快捷键设置按钮完整显示")
        if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".build/shortcut-settings-preview.png"))
        }
        buttons.first { $0.title == "保存" }!.performClick(nil)
        expect(closed && CaptureShortcut.load(from: defaults) == .defaultValue, "成功保存默认快捷键后关闭设置")
        let cancelled = ShortcutSettingsController(shortcut: custom)
        var cancelledApplied = false
        cancelled.onApply = { _ in cancelledApplied = true; return nil }
        cancelled.recorder.setShortcut(.defaultValue)
        descendants(cancelled.window!.contentView!).compactMap { $0 as? NSButton }.first { $0.title == "取消" }!.performClick(nil)
        expect(!cancelledApplied, "取消设置不应用候选快捷键")
    }
}
