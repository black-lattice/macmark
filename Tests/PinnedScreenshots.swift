import AppKit

extension Tests {
    @MainActor static func pinnedScreenshots(base: CGImage) throws {
        let bounds = CGRect(x: -1000, y: -400, width: 1000, height: 800)
        let preferred = CGRect(x: -800, y: 50, width: 300, height: 200)
        expect(PinnedScreenshotManager.placement(size: preferred.size, preferredFrame: preferred, within: bounds) == preferred,
               "锚定位置保留选区坐标，支持负坐标显示器")
        let large = PinnedScreenshotManager.placement(size: CGSize(width: 2000, height: 1000), preferredFrame: preferred, within: bounds)
        expect(bounds.contains(large) && large.width / large.height == 2, "大尺寸锚定截图按比例缩小并保持在屏幕内")
        let manager = PinnedScreenshotManager()
        let first = manager.pin(image: base, size: CGSize(width: 100, height: 100), preferredFrame: CGRect(x: 80, y: 80, width: 100, height: 100))
        let second = manager.pin(image: base, size: CGSize(width: 100, height: 100), preferredFrame: CGRect(x: 240, y: 80, width: 100, height: 100))
        expect(manager.screenshots.count == 2 && first.window !== second.window, "允许同时锚定多张独立截图")
        let panel = first.window as! NSPanel
        expect(panel.isVisible && panel.level == .floating && !panel.hidesOnDeactivate && panel.styleMask.contains(.nonactivatingPanel),
               "锚定截图保持置顶，切换应用不隐藏且不抢占应用焦点")
        expect(panel.collectionBehavior.contains(.canJoinAllSpaces) && panel.collectionBehavior.contains(.fullScreenAuxiliary),
               "锚定截图可随桌面切换并用于全屏应用")
        expect(panel.styleMask.contains(.borderless) && panel.hasShadow, "锚定截图没有边框，保留系统窗口阴影")
        expect(first.image.width == base.width && first.image.height == base.height, "锚定截图保留完整像素")
        let pinnedIDs = ScreenSnapshotSource.pinnedWindowIDs()
        expect(pinnedIDs.contains(CGWindowID(first.window!.windowNumber)) && pinnedIDs.contains(CGWindowID(second.window!.windowNumber)),
               "截图过滤例外包含全部可见锚定窗口")
        second.window?.orderOut(nil)
        expect(!ScreenSnapshotSource.pinnedWindowIDs().contains(CGWindowID(second.window!.windowNumber)), "隐藏的锚定窗口不会进入截图过滤例外")
        second.window?.orderFrontRegardless()
        let view = panel.contentView!
        func preview(_ name: NSAppearance.Name) -> NSBitmapImageRep {
            let appearance = NSAppearance(named: name)!
            panel.appearance = appearance
            view.needsDisplay = false; view.viewDidChangeEffectiveAppearance()
            expect(view.needsDisplay, "切换\(name.rawValue)外观后锚定窗口刷新阴影")
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            appearance.performAsCurrentDrawingAppearance { view.cacheDisplay(in: view.bounds, to: bitmap) }
            return bitmap
        }
        let light = preview(.aqua), dark = preview(.darkAqua)
        let y = light.pixelsHigh / 2
        expect(light.colorAt(x: 0, y: y) == dark.colorAt(x: 0, y: y)
               && light.colorAt(x: 0, y: y) == light.colorAt(x: light.pixelsWide / 2, y: y),
               "浅色、深色模式下截图边缘保持原色，没有绘制边框")
        expect(light.colorAt(x: light.pixelsWide / 2, y: y) == dark.colorAt(x: dark.pixelsWide / 2, y: y),
               "阴影外观变化不改变截图内容")
        panel.appearance = nil
        expect(view.acceptsFirstMouse(for: nil) && panel.becomesKeyOnlyIfNeeded, "在其他应用前台时可直接操作锚定截图")
        func event(_ type: NSEvent.EventType, x: CGFloat, y: CGFloat) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: y), modifierFlags: [], timestamp: 0,
                              windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        let origin = panel.frame.origin
        view.mouseDown(with: event(.leftMouseDown, x: 20, y: 20))
        view.mouseDragged(with: event(.leftMouseDragged, x: 70, y: 50))
        view.mouseUp(with: event(.leftMouseUp, x: 20, y: 20))
        expect(panel.frame.origin == CGPoint(x: origin.x + 50, y: origin.y + 30), "锚定图片可拖动移动位置")
        let menu = view.menu(for: event(.rightMouseDown, x: 20, y: 20))!
        let destroy = menu.item(withTitle: "销毁锚定截图")!
        NSApp.sendAction(destroy.action!, to: destroy.target, from: destroy)
        expect(manager.screenshots.count == 1 && manager.screenshots.first === second && !panel.isVisible,
               "右键菜单销毁当前锚定截图，不影响其他截图")
        expect(!ScreenSnapshotSource.pinnedWindowIDs().contains(CGWindowID(panel.windowNumber)), "销毁锚定截图后立即移除截图过滤例外")
        second.close()
        expect(manager.screenshots.isEmpty, "关闭锚定窗口后移除管理器中的引用")
        weak var released: PinnedScreenshotController?
        autoreleasepool {
            let temporary = manager.pin(image: base, size: CGSize(width: 100, height: 100), preferredFrame: preferred)
            released = temporary
            temporary.close()
        }
        expect(released == nil, "销毁后释放锚定窗口控制器")
        let size = CGSize(width: 300, height: 240)
        let window = SelectionWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        let selection = CGRect(x: 40, y: 50, width: 100, height: 100)
        let context = CaptureEditingContext(window: window, snapshot: base, selection: selection)
        let editor = EditorController(image: base, size: selection.size, captureContext: context)
        expect(!ScreenSnapshotSource.pinnedWindowIDs().contains(CGWindowID(window.windowNumber)), "截图选区和标注工具窗口不会被作为捕获例外")
        editor.onPin = { image, size, frame in manager.pin(image: image, size: size, preferredFrame: frame) }
        var closed = false
        editor.onClose = { closed = true }
        editor.choose(.text)
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: editor.canvas.convert(CGPoint(x: 10, y: 10), to: nil),
                                     modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                     eventNumber: 0, clickCount: 1, pressure: 1)!
        editor.canvas.mouseDown(with: down)
        (window.firstResponder as! NSTextView).insertText("锚定", replacementRange: NSRange(location: NSNotFound, length: 0))
        func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
        let pin = descendants(window.contentView!).compactMap { $0 as? NSButton }.first { $0.title == "锚定截图" }!
        pin.performClick(nil)
        let expected = editor.canvas.renderedImage()!
        expect(editor.canvas.marks.last?.text == "锚定", "锚定前自动提交正在输入的文字")
        expect(closed && !window.isVisible && manager.screenshots.count == 1, "工具栏锚定后结束原位编辑，锚定窗口独立保留")
        expect(manager.screenshots[0].image.dataProvider!.data! == expected.dataProvider!.data!, "锚定内容与完成标注后的导出图像一致")
        manager.screenshots[0].close()
    }
}
