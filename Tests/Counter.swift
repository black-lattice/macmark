import AppKit

extension Tests {
    @MainActor static func counters(base: CGImage) throws {
        let canvas = CanvasView(base: base, size: CGSize(width: 200, height: 200))
        let window = NSWindow(contentRect: canvas.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.close() }
        var confirmations = 0
        canvas.onConfirmCapture = { confirmations += 1 }
        canvas.tool = .counter
        func event(_ type: NSEvent.EventType, _ point: CGPoint, clicks: Int = 1) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                              windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
        }
        func click(_ point: CGPoint, clicks: Int = 1) {
            canvas.mouseDown(with: event(.leftMouseDown, point, clicks: clicks))
            canvas.mouseUp(with: event(.leftMouseUp, point, clicks: clicks))
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        }
        click(CGPoint(x: 50, y: 50)); click(CGPoint(x: 110, y: 50), clicks: 2)
        expect(canvas.marks.map(\.text) == ["1", "2"] && confirmations == 0, "序号连续单击递增，双击不误触截图确认")
        canvas.undo(); expect(canvas.marks.map(\.text) == ["1"], "序号支持撤销")
        canvas.redo(); expect(canvas.marks.map(\.text) == ["1", "2"], "序号支持重做")
        canvas.tool = .select; click(CGPoint(x: 110, y: 50)); canvas.deleteSelected()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        canvas.tool = .counter; click(CGPoint(x: 110, y: 60))
        expect(canvas.marks.last?.text == "2", "删除最后序号后继续从当前最大序号递增")
        canvas.tool = .select
        canvas.mouseDown(with: event(.leftMouseDown, CGPoint(x: 50, y: 50)))
        canvas.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 70, y: 80)))
        canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: 70, y: 80)))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        expect(canvas.marks[0].points == [CGPoint(x: 70, y: 80)], "选择工具可整体移动序号")
        canvas.setTextSize(40)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        expect(canvas.marks[0].fontSize == 40 && canvas.marks[0].bounds.width > 60, "选中序号后可调整大小")
        canvas.undo(); expect(canvas.marks[0].fontSize == 24, "序号大小调整支持撤销")
        let image = canvas.renderedImage()!
        let pixel = NSBitmapImageRep(cgImage: image).colorAt(x: 56, y: 80)!.usingColorSpace(.deviceRGB)!
        expect(pixel.redComponent > pixel.greenComponent + 0.2, "序号圆形背景正确导出到 PNG")
        let long = Annotation(tool: .counter, points: [CGPoint(x: 100, y: 100)], color: .yellow, width: 3, text: "1234", fontSize: 24)
        expect(long.bounds.width > canvas.marks[0].bounds.width && long.contains(CGPoint(x: 100, y: 100)), "多位序号自动扩展圆形并可命中")
        try Renderer.png(Renderer.image(base: base, logicalSize: canvas.logicalSize, marks: canvas.marks + [long])!)!
            .write(to: URL(fileURLWithPath: ".build/counter-preview.png"))
    }
}
