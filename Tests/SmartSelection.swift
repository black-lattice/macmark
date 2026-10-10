import AppKit

extension Tests {
    @MainActor static func windowSelection(base: CGImage) throws {
        func info(_ id: Int, _ rect: CGRect, pid: Int = 42, layer: Int = 0, alpha: Double = 1) -> [String: Any] {
            [kCGWindowNumber as String: id, kCGWindowOwnerPID as String: pid,
             kCGWindowLayer as String: layer, kCGWindowAlpha as String: alpha,
             kCGWindowBounds as String: rect.dictionaryRepresentation]
        }
        let front = CGRect(x: 40, y: 20, width: 120, height: 100)
        let back = CGRect(x: 10, y: 10, width: 180, height: 150)
        let pinned = CGRect(x: 170, y: 50, width: 20, height: 30)
        let frames = WindowSelection.frames(from: [info(1, front, pid: 7), info(2, front, layer: 25),
                                                   info(3, front, alpha: 0), info(4, pinned, pid: 7, layer: 3),
                                                   info(5, front), info(6, back)],
                                            primaryScreenTop: 200, ownPID: 7, pinnedIDs: [4])
        expect(frames.count == 3, "智能选区排除自身界面、系统高层窗口和透明窗口，保留锚定截图")
        let local = WindowSelection.localFrames(frames, display: CGRect(x: 0, y: 0, width: 200, height: 200))
        expect(local == [pinned, front, back], "窗口坐标转换后保留从前到后的遮挡顺序")
        let spanning = CGRect(x: -50, y: 160, width: 100, height: 80)
        expect(WindowSelection.localFrames([spanning], display: CGRect(x: -200, y: 0, width: 200, height: 200))
               == [CGRect(x: 150, y: 0, width: 50, height: 40)], "左侧负坐标显示器裁剪跨屏窗口")
        expect(WindowSelection.localFrames([spanning], display: CGRect(x: 0, y: 200, width: 200, height: 200))
               == [CGRect(x: 0, y: 160, width: 50, height: 40)], "上方显示器正确转换纵向坐标")
        expect(WindowSelection.localFrames([spanning], display: CGRect(x: 0, y: -200, width: 200, height: 200)).isEmpty,
               "不在当前显示器的窗口不参与吸附")
        let view = SelectionView(image: base, size: CGSize(width: 200, height: 200), windowFrames: local)
        let window = SelectionWindow(contentRect: CGRect(x: -200, y: 100, width: 200, height: 200),
                                     styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.close() }
        var selections: [CGRect] = []
        view.onSelect = { selections.append($0) }
        func event(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat, in target: NSView) -> NSEvent {
            if type == .mouseExited {
                return NSEvent.enterExitEvent(with: type, location: target.convert(CGPoint(x: x, y: y), to: nil),
                                              modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                              context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
            }
            return NSEvent.mouseEvent(with: type, location: target.convert(CGPoint(x: x, y: y), to: nil), modifierFlags: [],
                              timestamp: 0, windowNumber: window.windowNumber, context: nil,
                              eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        view.updateTrackingAreas()
        expect(view.trackingAreas.count == 1 && view.trackingAreas[0].options.contains(.activeAlways),
               "非关键显示器也跟踪悬停事件")
        view.mouseMoved(with: event(.mouseMoved, 60, 60, in: view))
        expect(view.selection == front && selections.isEmpty, "重叠区域悬停预览最前窗口，不提前进入编辑")
        view.mouseMoved(with: event(.mouseMoved, 20, 20, in: view))
        expect(view.selection == back, "移动到后方窗口露出的部分切换预览")
        view.mouseExited(with: event(.mouseExited, 201, 20, in: view))
        expect(view.selection == nil, "移出屏幕后清除旧窗口高亮")
        view.mouseDown(with: event(.leftMouseDown, 60, 60, in: view))
        view.mouseDragged(with: event(.leftMouseDragged, 61, 61, in: view))
        view.mouseUp(with: event(.leftMouseUp, 61, 61, in: view))
        expect(selections == [front], "无需先移动鼠标，点击轻微抖动仍选择整个窗口")
        view.mouseDown(with: event(.leftMouseDown, 80, 80, in: view))
        view.mouseDragged(with: event(.leftMouseDragged, 20, 30, in: view))
        expect(view.selection == CGRect(x: 20, y: 30, width: 60, height: 50), "拖动超过阈值立即切换自由框选")
        view.mouseUp(with: event(.leftMouseUp, 20, 30, in: view))
        expect(selections.last == CGRect(x: 20, y: 30, width: 60, height: 50), "反向拖动提交自由选区而非窗口")
        view.mouseDown(with: event(.leftMouseDown, 80, 80, in: view))
        view.mouseDragged(with: event(.leftMouseDragged, 120, 120, in: view))
        view.mouseUp(with: event(.leftMouseUp, 81, 81, in: view))
        expect(selections.count == 2, "拖动后回到起点不会误触窗口点击")
        view.mouseDown(with: event(.leftMouseDown, 195, 195, in: view))
        view.mouseUp(with: event(.leftMouseUp, 195, 195, in: view))
        expect(selections.count == 2 && view.selection == nil, "桌面空白处点击不会创建无效选区")
        view.mouseDown(with: event(.leftMouseDown, 195, 195, in: view))
        view.mouseDragged(with: event(.leftMouseDragged, 210, 220, in: view))
        view.mouseUp(with: event(.leftMouseUp, 210, 220, in: view))
        expect(selections.last == CGRect(x: 195, y: 195, width: 5, height: 5), "拖动出屏幕仍裁剪到屏幕边界")

        let pending = SelectionView(size: view.bounds.size, windowFrames: local)
        window.contentView = pending
        var delivered: CGRect?
        pending.onSelect = { delivered = $0 }
        pending.mouseDown(with: event(.leftMouseDown, 60, 60, in: pending))
        pending.mouseUp(with: event(.leftMouseUp, 60, 60, in: pending))
        pending.mouseMoved(with: event(.mouseMoved, 20, 20, in: pending))
        expect(delivered == nil && pending.selection == front, "截图尚未就绪时锁定已点击的窗口，不随悬停改变")
        pending.updateSnapshot(base)
        expect(delivered == front, "截图就绪后交付此前点击的窗口范围")
        var cancelled = false
        pending.onCancel = { cancelled = true }
        pending.rightMouseDown(with: event(.rightMouseDown, 60, 60, in: pending))
        expect(cancelled, "智能选区保留右键取消")

        let previewSize = CGSize(width: 600, height: 400)
        let preview = SelectionView(image: base, size: previewSize,
                                    windowFrames: [CGRect(x: 140, y: 100, width: 340, height: 240)])
        window.setContentSize(previewSize); window.contentView = preview
        preview.mouseMoved(with: event(.mouseMoved, 200, 200, in: preview))
        if let bitmap = preview.bitmapImageRepForCachingDisplay(in: preview.bounds) {
            preview.cacheDisplay(in: preview.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".build/smart-selection-preview.png"))
        }
    }
}
