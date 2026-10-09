import AppKit

@main
enum Tests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        guard condition() else { fatalError("FAIL: \(message)") }
        print("PASS: \(message)")
    }
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let reversed = Geometry.rect(from: CGPoint(x: 90, y: 80), to: CGPoint(x: 10, y: 20))
        expect(reversed == CGRect(x: 10, y: 20, width: 80, height: 60), "反向拖动选区")
        let crop = Geometry.cropRect(selection: reversed, screenSize: CGSize(width: 100, height: 100),
                                     imageSize: CGSize(width: 200, height: 200))
        expect(crop == CGRect(x: 20, y: 40, width: 160, height: 120), "Retina 选区映射")
        let clipped = Geometry.cropRect(selection: CGRect(x: -10, y: 90, width: 30, height: 40),
                                        screenSize: CGSize(width: 100, height: 100), imageSize: CGSize(width: 100, height: 100))
        expect(clipped == CGRect(x: 0, y: 90, width: 20, height: 10), "越界选区裁切")
        let horizontal = Geometry.constrained(CGPoint(x: 90, y: 12), from: CGPoint(x: 10, y: 10))
        expect(abs(horizontal.y - 10) < 0.001, "Shift 横线约束")
        var arrow = Annotation(tool: .arrow, points: [CGPoint(x: 10, y: 20), CGPoint(x: 80, y: 20)], color: .red, width: 3)
        expect(arrow.contains(CGPoint(x: 50, y: 22)), "箭头命中")
        expect(!arrow.contains(CGPoint(x: 50, y: 45)), "箭头远处不命中")
        arrow.move(by: CGPoint(x: 0, y: 10))
        expect(arrow.points[0].y == 30, "移动标注")
        let box = Annotation(tool: .rectangle, points: [CGPoint(x: 10, y: 10), CGPoint(x: 90, y: 90)], color: .blue, width: 3)
        expect(box.contains(CGPoint(x: 10, y: 50)), "矩形边缘命中")
        expect(!box.contains(CGPoint(x: 50, y: 50)), "矩形内部不拦截其他标注")
        let ctx = CGContext(data: nil, width: 200, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(NSColor.white.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        ctx.setFillColor(NSColor.green.cgColor); ctx.fill(CGRect(x: 0, y: 160, width: 40, height: 40))
        let base = ctx.makeImage()!
        let size = CGSize(width: 100, height: 100)
        let line = Annotation(tool: .line, points: [CGPoint(x: 30, y: 25), CGPoint(x: 85, y: 25)], color: .red, width: 3)
        let text = Annotation(tool: .text, points: [CGPoint(x: 20, y: 60)], color: .black, width: 3, text: "轻截 MacMark")
        let exported = Renderer.image(base: base, logicalSize: size, marks: [line, arrow, box, text])!
        expect(exported.width == 200 && exported.height == 200, "导出保留原始像素")
        let rep = NSBitmapImageRep(cgImage: exported)
        let pixel = rep.colorAt(x: 100, y: 50)!.usingColorSpace(.deviceRGB)!
        expect(pixel.redComponent > 0.9 && pixel.greenComponent < 0.2, "导出直线位置及颜色正确")
        let upper = rep.colorAt(x: 20, y: 20)!.usingColorSpace(.deviceRGB)!
        let lower = rep.colorAt(x: 20, y: 180)!.usingColorSpace(.deviceRGB)!
        expect(upper.greenComponent > 0.9 && upper.redComponent < 0.2, "底图顶部方向正确")
        expect(lower.redComponent > 0.9, "底图底部方向正确")
        let png = Renderer.png(exported)!
        expect(NSBitmapImageRep(data: png)?.pixelsWide == 200, "PNG 编码解码")
        try png.write(to: URL(fileURLWithPath: ".build/annotation-preview.png"))
        let canvas = CanvasView(base: base, size: size)
        canvas.tool = .line
        func event(_ type: NSEvent.EventType, x: CGFloat, y: CGFloat) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: y), modifierFlags: [], timestamp: 0,
                              windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        canvas.mouseDown(with: event(.leftMouseDown, x: 10, y: 10))
        canvas.mouseDragged(with: event(.leftMouseDragged, x: 80, y: 50))
        canvas.mouseUp(with: event(.leftMouseUp, x: 80, y: 50))
        expect(canvas.marks.count == 1, "画布绘制提交")
        canvas.undo()
        expect(canvas.marks.isEmpty, "撤销绘制")
        canvas.redo()
        expect(canvas.marks.count == 1, "重做绘制")
        canvas.tool = .select
        canvas.mouseDown(with: event(.leftMouseDown, x: 45, y: 30))
        canvas.mouseUp(with: event(.leftMouseUp, x: 45, y: 30))
        canvas.deleteSelected()
        expect(canvas.marks.isEmpty, "选中并删除标注")
        canvas.undo()
        expect(canvas.marks.count == 1, "撤销删除")
        canvas.mouseDown(with: event(.leftMouseDown, x: 45, y: 30))
        canvas.mouseDragged(with: event(.leftMouseDragged, x: 55, y: 40))
        canvas.mouseUp(with: event(.leftMouseUp, x: 55, y: 40))
        expect(canvas.marks[0].points[0] == CGPoint(x: 20, y: 20), "拖动标注")
        canvas.undo()
        expect(canvas.marks[0].points[0] == CGPoint(x: 10, y: 10), "撤销移动")
        try preview()
        print("通过 \(checks) 项检查，架构：\(ProcessInfo.processInfo.environment["RUNNER_ARCH"] ?? "local")")
    }
}
