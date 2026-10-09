import AppKit

extension Tests {
    @MainActor static func captureEditing(snapshot: CGImage, size: CGSize) throws {
        let bounds = CGRect(origin: .zero, size: CGSize(width: 1200, height: 800))
        let toolbarSize = CGSize(width: 580, height: 128)
        let middle = CGRect(x: 300, y: 200, width: 400, height: 300)
        let below = CaptureEditorView.toolbarFrame(selection: middle, size: toolbarSize, within: bounds)
        expect(below.minY > middle.maxY && !below.intersects(middle), "工具栏优先放在选区下方")
        expect(below.midX == middle.midX, "工具栏相对选区水平居中")
        let bottom = CGRect(x: 900, y: 600, width: 280, height: 180)
        let above = CaptureEditorView.toolbarFrame(selection: bottom, size: toolbarSize, within: bounds)
        expect(above.maxY < bottom.minY && bounds.contains(above), "屏幕底部选区的工具栏上移并避免越界")
        let tiny = CGRect(x: 0, y: 0, width: 2, height: 2)
        let tinyToolbar = CaptureEditorView.toolbarFrame(selection: tiny, size: toolbarSize, within: bounds)
        expect(bounds.contains(tinyToolbar), "极小边缘选区仍可使用全部工具")
        let full = CaptureEditorView.toolbarFrame(selection: bounds, size: toolbarSize, within: bounds)
        expect(bounds.contains(full), "全屏选区的工具栏保持在屏幕内")

        let selection = CGRect(x: 32, y: 100, width: size.width - 64, height: 220)
        let pixels = Geometry.cropRect(selection: selection, screenSize: size,
                                       imageSize: CGSize(width: snapshot.width, height: snapshot.height))
        let cropped = snapshot.cropping(to: pixels)!
        let window = SelectionWindow(contentRect: CGRect(x: -size.width, y: 40, width: size.width, height: size.height),
                                     styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = SelectionView(image: snapshot, size: size)
        let originalFrame = window.frame
        let context = CaptureEditingContext(window: window, snapshot: snapshot, selection: selection)
        let editor = EditorController(image: cropped, size: selection.size, captureContext: context)
        let canvas = editor.canvas
        let view = window.contentView as! CaptureEditorView
        let toolbar = view.subviews.compactMap { $0 as? CaptureToolbarView }.first!
        view.layoutSubtreeIfNeeded()
        expect(editor.window === window && window.frame == originalFrame, "复用原截图窗口，不移动到主屏或居中")
        expect(canvas.frame == selection && canvas.scale == 1, "截图画布保持原选区位置及比例")
        expect(window.firstResponder === canvas, "松开选区后画布立即接受快捷键")
        expect(toolbar.frame.width > 400 && toolbar.frame.height > 80 && view.bounds.contains(toolbar.frame), "浮动工具栏布局完整且不越界")
        expect(!toolbar.frame.intersects(selection), "实际工具栏不遮挡有可用空间的选区")
        expect(toolbar.frame.midX == selection.midX, "实际图标栏与截图中心对齐")
        view.setFrameSize(CGSize(width: size.width, height: 420))
        view.needsLayout = true; view.layoutSubtreeIfNeeded()
        expect(toolbar.convert(toolbar.barFrame, to: view).minY > selection.maxY && toolbar.paletteAbove,
               "下方仅够图标栏时设置面板向上展开")
        view.setFrameSize(CGSize(width: size.width, height: 350))
        view.needsLayout = true; view.layoutSubtreeIfNeeded()
        expect(toolbar.convert(toolbar.barFrame, to: view).maxY < selection.minY, "下方空间不足时图标栏动态切换到上方")
        view.setFrameSize(size)
        view.needsLayout = true; view.layoutSubtreeIfNeeded()
        func descendants(_ parent: NSView) -> [NSView] {
            parent.subviews.flatMap { [$0] + descendants($0) }
        }
        let buttons = descendants(toolbar).compactMap { $0 as? NSButton }
        let mainButtons = buttons.filter { $0.superview !== toolbar.palette }
        expect(Set(mainButtons.map { $0.convert($0.bounds, to: toolbar).midY }).count == 1, "所有主要操作位于同一排图标栏")
        expect(buttons.allSatisfy { toolbar.bounds.contains($0.convert($0.bounds, to: toolbar)) }, "全部工具按钮完整显示")
        let sizeControls = toolbar.palette.subviews.compactMap { $0 as? AnnotationSizeSlider }
        func changeSize(_ value: Double, brush: Bool = false) {
            let slider = sizeControls[brush ? 1 : 0].slider
            slider.doubleValue = value
            NSApp.sendAction(slider.action!, to: slider.target, from: slider)
        }
        for tool in MarkTool.allCases {
            let button = buttons.first { $0.identifier?.rawValue == tool.rawValue }!
            button.performClick(nil)
            expect(canvas.tool == tool && button.state == .on, "原位工具栏切换\(tool.title)")
        }
        for tool in [MarkTool.blur, .mosaic] {
            editor.choose(tool)
            changeSize(5)
            expect(canvas.redactionStrength == 5 && canvas.markWidth == 3, "\(tool.title)强度设置独立于线宽")
            expect(toolbar.palette.subviews.compactMap { $0 as? NSButton }.filter { $0.toolTip == "红色" }.allSatisfy(\.isHidden),
                   "遮挡工具隐藏无关颜色选项")
            changeSize(3)
            let mode = toolbar.palette.subviews.compactMap { $0 as? NSSegmentedControl }.first!
            mode.selectedSegment = RedactionMode.brush.rawValue
            NSApp.sendAction(mode.action!, to: mode.target, from: mode)
            let brush = sizeControls[1]
            expect(canvas.redactionMode == .brush && !brush.isHidden, "\(tool.title)可切换涂抹模式并显示笔刷设置")
            changeSize(48, brush: true)
            expect(canvas.redactionBrushSize == 48 && canvas.redactionStrength == 3, "笔刷大小独立于遮挡强度")
            mode.selectedSegment = RedactionMode.region.rawValue
            NSApp.sendAction(mode.action!, to: mode.target, from: mode)
            expect(canvas.redactionMode == .region && brush.isHidden, "\(tool.title)保留原有框选方式")
        }
        editor.choose(.arrow)
        let settings = buttons.first { $0.title == "标注设置" }!
        settings.performClick(nil)
        expect(toolbar.palette.isHidden, "标注设置按钮可收起小面板")
        expect(toolbar.frame.height == 40 && toolbar.frame.midX == selection.midX, "收起面板后重新计算居中位置及所需空间")
        settings.performClick(nil)
        expect(!toolbar.palette.isHidden, "标注设置按钮可展开小面板")
        buttons.first { $0.identifier?.rawValue == MarkTool.select.rawValue }!.performClick(nil)
        expect(toolbar.palette.isHidden, "选择工具收起颜色与粗细面板")
        buttons.first { $0.identifier?.rawValue == MarkTool.arrow.rawValue }!.performClick(nil)
        expect(!toolbar.palette.isHidden, "绘图工具显示对应设置面板")
        changeSize(5)
        expect(canvas.markWidth == 5 && window.firstResponder === canvas, "粗细滑块修改线宽并恢复画布焦点")
        changeSize(3)
        let floatingFrame = toolbar.frame
        toolbar.setFrameOrigin(CGPoint(x: selection.minX + 10, y: selection.minY + 10))
        let clearPoint = CGPoint(x: toolbar.frame.minX + 8, y: toolbar.frame.minY + 70)
        expect(view.hitTest(clearPoint) === canvas, "设置面板旁的透明区域不阻挡画布操作")
        toolbar.frame = floatingFrame
        func event(_ type: NSEvent.EventType, x: CGFloat, y: CGFloat) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(CGPoint(x: x, y: y), to: nil), modifierFlags: [], timestamp: 0,
                              windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        let blue = buttons.first { $0.toolTip == "蓝色" }!
        blue.performClick(nil)
        expect(canvas.markColor == .systemBlue && blue.state == .on, "颜色按钮切换标注颜色")
        let swatch = NSBitmapImageRep(data: blue.image!.tiffRepresentation!)!
        let color = swatch.colorAt(x: swatch.pixelsWide / 2, y: swatch.pixelsHigh / 2)!.usingColorSpace(.deviceRGB)!
        expect(color.blueComponent > color.redComponent, "颜色按钮显示真实蓝色色块")
        buttons.first { $0.toolTip == "红色" }!.performClick(nil)
        let originalToolbar = toolbar.frame
        toolbar.mouseDown(with: event(.leftMouseDown, x: 300, y: 200))
        toolbar.mouseDragged(with: event(.leftMouseDragged, x: 4000, y: 4000))
        toolbar.mouseUp(with: event(.leftMouseUp, x: 4000, y: 4000))
        expect(view.bounds.contains(toolbar.frame) && toolbar.frame.origin != originalToolbar.origin, "工具栏可拖动且被限制在屏幕内")
        toolbar.frame = originalToolbar
        buttons.first { $0.identifier?.rawValue == MarkTool.arrow.rawValue }!.performClick(nil)
        canvas.mouseDown(with: event(.leftMouseDown, x: 400, y: 140))
        canvas.mouseDragged(with: event(.leftMouseDragged, x: 270, y: 140))
        canvas.mouseUp(with: event(.leftMouseUp, x: 270, y: 140))
        expect(canvas.marks.first?.points.first == CGPoint(x: 400, y: 140), "原位绘制使用选区局部坐标")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        let arrowBeforeWidth = canvas.marks[0]
        changeSize(5)
        expect(canvas.marks[0].width == 5 && canvas.marks[0].bounds.height > arrowBeforeWidth.bounds.height,
               "工具栏粗细设置立即改变已选中箭头的箭身和箭头宽度")
        expect(canvas.marks[0].points == arrowBeforeWidth.points, "修改箭头粗细保持端点位置")
        canvas.undo()
        expect(canvas.marks[0].width == 3, "箭头粗细修改可以撤销")
        canvas.redo()
        expect(canvas.marks[0].width == 5, "箭头粗细修改可以重做")
        canvas.undo()
        changeSize(3)
        let undo = buttons.first { $0.title == "撤销" }!
        undo.performClick(nil)
        expect(canvas.marks.isEmpty && window.firstResponder === canvas, "原位撤销并恢复键盘焦点")
        buttons.first { $0.title == "重做" }!.performClick(nil)
        expect(canvas.marks.count == 1, "原位重做")
        let image = canvas.renderedImage()!
        expect(image.width == cropped.width && image.height == cropped.height, "原位导出仅包含选区并保留 Retina 像素")
        if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let arrow = buttons.first { $0.identifier?.rawValue == MarkTool.arrow.rawValue }!
            func pixel(_ point: CGPoint) -> NSColor {
                let location = arrow.convert(point, to: view)
                return bitmap.colorAt(x: Int(location.x * CGFloat(bitmap.pixelsWide) / view.bounds.width),
                                      y: Int(location.y * CGFloat(bitmap.pixelsHigh) / view.bounds.height))!.usingColorSpace(.deviceRGB)!
            }
            let center = pixel(CGPoint(x: 15, y: 15))
            let margin = pixel(CGPoint(x: 3, y: 15))
            expect(center.blueComponent - center.redComponent > 0.25 && center.blueComponent - center.greenComponent > 0.1,
                   "选中工具的图标本身呈蓝色高亮")
            expect(margin.redComponent > 0.95 && margin.greenComponent > 0.95 && margin.blueComponent > 0.95,
                   "选中工具没有增加按钮背景或边框")
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".build/capture-editor-preview.png"))
        }
        let cancelHandler = canvas.onCancel
        editor.choose(.text)
        blue.performClick(nil)
        try textEditing(canvas: canvas, window: window, view: view)
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                      windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
                                      charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        var textCancelled = false
        canvas.onCancel = { textCancelled = true }
        canvas.tool = .text
        canvas.mouseDown(with: event(.leftMouseDown, x: 20, y: 20))
        expect(window.firstResponder is NSTextView, "原位文字工具激活输入框")
        (window.firstResponder as! NSTextView).keyDown(with: escape)
        expect(textCancelled, "文字输入期间取消命令沿响应链结束截图")
        canvas.commitText()
        canvas.onCancel = cancelHandler
        window.makeFirstResponder(canvas)
        var closed = false
        editor.onClose = { closed = true }
        canvas.keyDown(with: escape)
        expect(closed && !window.isVisible, "Escape 结束原位截图并执行清理回调")
        var rightCancelled = false
        canvas.onCancel = { rightCancelled = true }
        canvas.rightMouseDown(with: event(.rightMouseDown, x: 20, y: 20))
        expect(rightCancelled, "原位画布右键取消")
        try upperToolbarPreview(snapshot: snapshot, size: size)
    }
    @MainActor private static func upperToolbarPreview(snapshot: CGImage, size: CGSize) throws {
        let selection = CGRect(x: 300, y: 270, width: 320, height: 160)
        let pixels = Geometry.cropRect(selection: selection, screenSize: size,
                                       imageSize: CGSize(width: snapshot.width, height: snapshot.height))
        let window = SelectionWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless,
                                     backing: .buffered, defer: false)
        window.contentView = SelectionView(image: snapshot, size: size)
        let context = CaptureEditingContext(window: window, snapshot: snapshot, selection: selection)
        let editor = EditorController(image: snapshot.cropping(to: pixels)!, size: selection.size, captureContext: context)
        let view = window.contentView!
        view.layoutSubtreeIfNeeded()
        let toolbar = view.subviews.compactMap { $0 as? CaptureToolbarView }.first!
        let bar = toolbar.convert(toolbar.barFrame, to: view)
        expect(toolbar.paletteAbove && bar.maxY == selection.minY - 8 && bar.midX == selection.midX,
               "上方图标栏紧邻选区并保持居中")
        expect(toolbar.palette.convert(toolbar.palette.bounds, to: view).maxY < bar.minY,
               "上方设置面板朝屏幕上方展开")
        if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let badge = bitmap.colorAt(x: Int((selection.minX + 3) * CGFloat(bitmap.pixelsWide) / view.bounds.width),
                                       y: Int((selection.maxY + 12) * CGFloat(bitmap.pixelsHigh) / view.bounds.height))!.usingColorSpace(.deviceRGB)!
            expect(badge.blueComponent - badge.redComponent > 0.4, "窄选区的尺寸标签自动避开上方工具栏")
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".build/capture-editor-above-preview.png"))
        }
        editor.close()
    }
}
