import AppKit

extension Tests {
    @MainActor static func sizeSliders(base: CGImage) throws {
        let size = CGSize(width: 300, height: 240)
        func change(_ control: AnnotationSizeSlider, to value: Double) {
            control.slider.doubleValue = value
            NSApp.sendAction(control.slider.action!, to: control.slider.target, from: control.slider)
        }
        func event(_ type: NSEvent.EventType, canvas: CanvasView, x: CGFloat, y: CGFloat) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(CGPoint(x: x * canvas.scale, y: y * canvas.scale), to: nil),
                              modifierFlags: [], timestamp: 0, windowNumber: canvas.window!.windowNumber, context: nil,
                              eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        for tool in [MarkTool.rectangle, .line, .arrow, .pen] {
            let canvas = CanvasView(base: base, size: size)
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = canvas
            canvas.tool = tool
            canvas.mouseDown(with: event(.leftMouseDown, canvas: canvas, x: 40, y: 40))
            canvas.mouseDragged(with: event(.leftMouseDragged, canvas: canvas, x: 180, y: 120))
            canvas.mouseUp(with: event(.leftMouseUp, canvas: canvas, x: 180, y: 120))
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
            let original = canvas.marks[0]
            let control = AnnotationSizeSlider()
            control.bindStyle(to: canvas); control.configureStyle(for: canvas)
            expect(control.slider.isContinuous, "\(tool.title)使用连续调节的粗细滑块")
            control.onBegin?(); change(control, to: 4.4); change(control, to: 7.2); control.onEnd?()
            expect(abs(canvas.marks[0].width - 7.2) < 0.01 && canvas.marks[0].points == original.points,
                   "滑块实时改变\(tool.title)粗细并保持位置")
            canvas.undo()
            expect(canvas.marks.count == 1 && canvas.marks[0].width == 3, "一次撤销回退整次\(tool.title)滑块拖动")
            canvas.redo()
            expect(abs(canvas.marks[0].width - 7.2) < 0.01, "重做恢复滑块调节后的粗细")
            window.close()
        }
        let canvas = CanvasView(base: base, size: size)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        canvas.markWidth = 10; canvas.tool = .text
        canvas.mouseDown(with: event(.leftMouseDown, canvas: canvas, x: 20, y: 20))
        let input = window.firstResponder as! NSTextView
        input.insertText("第一行\n第二行", replacementRange: NSRange(location: NSNotFound, length: 0))
        expect(input.font!.pointSize == 18, "文字字号独立于绘图线宽")
        let font = AnnotationSizeSlider()
        font.bindStyle(to: canvas); font.configureStyle(for: canvas)
        change(font, to: 33)
        expect(input.font!.pointSize == 33 && window.firstResponder === input, "字号滑块实时调整正在输入的文字并保留编辑焦点")
        canvas.commitText()
        expect(canvas.marks.last!.fontSize == 33 && (canvas.marks.last!.textAttributes[.font] as! NSFont).pointSize == 33,
               "字号调整在完成和导出时保持一致")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        font.onBegin?(); change(font, to: 24); change(font, to: 12); font.onEnd?()
        expect(canvas.marks.last!.fontSize == 12 && canvas.markWidth == 10, "选中文字后滑块修改现有字号且不影响线宽")
        canvas.undo()
        expect(canvas.marks.last!.fontSize == 33, "一次撤销恢复整次字号拖动前的大小")
        for tool in [MarkTool.blur, .mosaic] {
            canvas.tool = tool; canvas.redactionMode = .brush
            let brush = AnnotationSizeSlider(); brush.bindBrush(to: canvas)
            brush.configure(title: "笔刷", value: canvas.redactionBrushSize, range: 6...200, step: 1)
            change(brush, to: 52)
            for scale in [CGFloat(0.5), 1, 2] {
                canvas.setFrameSize(CGSize(width: size.width * scale, height: size.height * scale))
                canvas.mouseMoved(with: event(.mouseMoved, canvas: canvas, x: 180, y: 160))
                let preview = canvas.subviews.compactMap { $0 as? BrushCursorPreview }.first!
                expect(NSCursor.current === AnnotationCursor.brush && preview.center == CGPoint(x: 180 * scale, y: 160 * scale)
                       && preview.diameter == 52 * scale, "\(tool.title)圆形光标在不同缩放下准确显示笔刷大小")
            }
            canvas.setFrameSize(size)
            canvas.mouseDown(with: event(.leftMouseDown, canvas: canvas, x: 180, y: 160))
            canvas.mouseUp(with: event(.leftMouseUp, canvas: canvas, x: 180, y: 160))
            expect(canvas.marks.last!.brushSize == 52, "涂抹使用滑块指定的笔刷大小")
            canvas.mouseExited(with: event(.mouseMoved, canvas: canvas, x: 180, y: 160))
            let preview = canvas.subviews.compactMap { $0 as? BrushCursorPreview }.first!
            expect(preview.center == nil && NSCursor.current === NSCursor.arrow, "移出画布后恢复普通鼠标，圆形光标不残留")
            canvas.redactionMode = .region
            canvas.mouseMoved(with: event(.mouseMoved, canvas: canvas, x: 250, y: 220))
            expect(preview.center == nil && NSCursor.current === NSCursor.crosshair, "切回框选恢复原有光标")
        }
        window.close()
    }
}
