import AppKit

extension Tests {
    @MainActor static func screenshotHistory(base: CGImage) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MacMarkHistoryTests-" + UUID().uuidString)
        let directory = root.appendingPathComponent("History")
        let domain = "MacMarkHistoryTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { try? FileManager.default.removeItem(at: root); defaults.removePersistentDomain(forName: domain) }
        let store = ScreenshotHistory(directory: directory, defaults: defaults)
        expect(store.entries.isEmpty && store.isEnabled, "新用户历史默认开启且为空")
        let first = try store.add(base)!
        let duplicate = try store.add(base)
        expect(store.entries.count == 1 && duplicate == first, "重复导出同一最终图片不重复占用历史")
        for number in 1...21 {
            let mark = Annotation(tool: .counter, points: [CGPoint(x: 100, y: 100)], color: .red, width: 3, text: String(number), fontSize: 24)
            try store.add(Renderer.image(base: base, logicalSize: CGSize(width: 200, height: 200), marks: [mark])!)
        }
        expect(store.entries.count == 20 && !FileManager.default.fileExists(atPath: store.url(for: first).path), "历史最多 20 张并删除最旧的图片文件")
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        expect(files.filter { $0.pathExtension == "png" }.count == 20, "历史上限同时约束磁盘 PNG 数量")
        let restored = ScreenshotHistory(directory: directory, defaults: defaults)
        expect(restored.entries == store.entries, "重启后恢复历史顺序和元数据")
        let latest = restored.entries[0]
        expect(restored.image(for: latest)?.width == 200 && restored.thumbnail(for: latest, maxSize: 80)!.size.width <= 80,
               "历史原图保留像素，预览按需生成缩略图")
        restored.isEnabled = false
        let ignored = try restored.add(base)
        expect(ignored == nil && restored.entries.count == 20 && !ScreenshotHistory(directory: directory, defaults: defaults).isEnabled,
               "关闭历史后不写新图片，开关在重启后保留")
        let controller = HistoryWindowController(history: restored)
        controller.present()
        let window = controller.window!
        func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
        let buttons = descendants(window.contentView!).compactMap { $0 as? NSButton }
        var opened: CGImage?
        controller.onOpen = { opened = $0 }
        buttons.first { $0.title == "继续标注" }!.performClick(nil)
        expect(opened?.width == 200, "历史可重新打开完整分辨率图片继续标注")
        buttons.first { $0.title == "复制图片" }!.performClick(nil)
        expect(NSBitmapImageRep(data: NSPasteboard.general.data(forType: .png)!)?.pixelsWide == 200, "历史复制使用原图而非缩略图")
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearance)
            controller.reload()
            window.contentView!.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
            let view = window.contentView!
            let list = descendants(view).compactMap { $0 as? NSScrollView }.first!
            expect(list.frame.height > view.bounds.height - 100, "历史列表随窗口高度填满可用空间")
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            window.appearance!.performAsCurrentDrawingAppearance { view.cacheDisplay(in: view.bounds, to: rep) }
            try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".build/history-\(appearance.rawValue)-preview.png"))
        }
        window.setContentSize(CGSize(width: 680, height: 400)); window.contentView!.layoutSubtreeIfNeeded()
        expect(buttons.filter { $0.title == "复制图片" || $0.title == "继续标注" }.allSatisfy {
            window.contentView!.bounds.contains($0.convert($0.bounds, to: window.contentView))
        }, "历史窗口最小尺寸下主要按钮保持可见")
        let unrelated = root.appendingPathComponent("export.png"); try Data("keep".utf8).write(to: unrelated)
        try restored.clear()
        expect(restored.entries.isEmpty && !FileManager.default.fileExists(atPath: directory.path)
               && FileManager.default.fileExists(atPath: unrelated.path), "清空仅删除历史目录，保留另行导出的文件")
        expect(buttons.first { $0.title == "复制图片" }!.isEnabled == false, "清空后禁用没有目标的历史操作")
        restored.isEnabled = true; try restored.add(base)
        expect(restored.entries.count == 1, "清空后可以重新开始记录")
        try Data("invalid".utf8).write(to: directory.appendingPathComponent("index.json"))
        expect(ScreenshotHistory(directory: directory, defaults: defaults).loadError != nil, "损坏的历史索引显示读取错误而不崩溃")
        controller.close()
        let editor = EditorController(image: base, size: CGSize(width: 200, height: 200))
        var exports = 0; editor.onExport = { _, _ in exports += 1 }
        editor.copyImage(); expect(exports == 1, "成功复制图片触发历史记录")
        editor.onPin = { _, _, _ in }; editor.pinImage()
        expect(exports == 2, "成功锚定图片触发历史记录")
        editor.close(); expect(exports == 2, "关闭或取消编辑不额外保存历史")
    }
}
