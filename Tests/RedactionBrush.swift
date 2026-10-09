import AppKit

extension Tests {
    @MainActor static func redactionBrush(base: CGImage) throws {
        let size = CGSize(width: 400, height: 240)
        let context = CGContext(data: nil, width: 800, height: 480, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.translateBy(x: 0, y: 480); context.scaleBy(x: 2, y: -2)
        for y in stride(from: 0, to: 240, by: 4) {
            for x in stride(from: 0, to: 400, by: 4) {
                context.setFillColor(((x + y) / 4 % 2 == 0 ? NSColor.white : .black).cgColor)
                context.fill(CGRect(x: x, y: y, width: 4, height: 4))
            }
        }
        let texture = context.makeImage()!
        let original = NSBitmapImageRep(cgImage: texture)
        func gray(_ bitmap: NSBitmapImageRep, x: Int, y: Int) -> CGFloat {
            bitmap.colorAt(x: x * 2, y: y * 2)!.usingColorSpace(.deviceRGB)!.redComponent
        }
        for tool in [MarkTool.blur, .mosaic] {
            let canvas = CanvasView(base: texture, size: size)
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = canvas
            canvas.tool = tool
            func event(_ type: NSEvent.EventType, _ p: CGPoint) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: canvas.convert(p, to: nil), modifierFlags: [], timestamp: 0,
                                  windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            func draw(_ points: [CGPoint]) {
                canvas.mouseDown(with: event(.leftMouseDown, points[0]))
                for p in points.dropFirst() { canvas.mouseDragged(with: event(.leftMouseDragged, p)) }
                canvas.mouseUp(with: event(.leftMouseUp, points.last!))
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
            }
            draw([CGPoint(x: 48, y: 32), CGPoint(x: 208, y: 184)])
            canvas.redactionMode = .brush
            let points = [CGPoint(x: 140, y: 100), CGPoint(x: 280, y: 100), CGPoint(x: 280, y: 200)]
            draw(points)
            let stroke = canvas.marks[1]
            expect(canvas.marks.count == 2 && stroke.isBrushRedaction && stroke.points == points,
                   "\(tool.title)可从已有遮挡区域内部开始连续涂抹，并与框选并存")
            expect(stroke.contains(CGPoint(x: 240, y: 100)) && !stroke.contains(CGPoint(x: 240, y: 160)),
                   "涂抹命中范围沿鼠标轨迹，不覆盖轨迹包围框的空白部分")
            expect(stroke.editingHandles.isEmpty && stroke.selectionPath(scale: 1).bounds == stroke.redactionPath.bounds,
                   "涂抹选中轮廓贴合笔刷边缘")
            let image = canvas.renderedImage()!
            let bitmap = NSBitmapImageRep(cgImage: image)
            expect(abs(gray(bitmap, x: 240, y: 100) - gray(original, x: 240, y: 100)) > 0.15,
                   "\(tool.title)涂抹实际遮挡笔刷内的截图细节")
            expect(abs(gray(bitmap, x: 240, y: 160) - gray(original, x: 240, y: 160)) < 0.01,
                   "\(tool.title)涂抹不改变轨迹外的截图内容")
            let preview = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
            canvas.cacheDisplay(in: canvas.bounds, to: preview)
            let previewColor = preview.colorAt(x: Int(240 * CGFloat(preview.pixelsWide) / size.width),
                                               y: Int(100 * CGFloat(preview.pixelsHigh) / size.height))!.usingColorSpace(.deviceRGB)!
            expect(abs(previewColor.redComponent - gray(bitmap, x: 240, y: 100)) < 0.04, "涂抹预览与导出一致")
            try Renderer.png(image)!.write(to: URL(fileURLWithPath: ".build/\(tool.rawValue)-brush-preview.png"))
            draw([CGPoint(x: 340, y: 60)])
            expect(canvas.marks.last!.points.count == 1 && canvas.marks.last!.bounds.size == CGSize(width: 24, height: 24),
                   "单击可生成圆形遮挡笔触")
            canvas.undo(); canvas.undo()
            expect(canvas.marks.count == 1 && !canvas.marks[0].isBrushRedaction, "两次撤销分别移除两条笔触并保留框选区域")
            canvas.redo()
            expect(canvas.marks.last!.points == points, "重做恢复整条涂抹轨迹")
            canvas.redactionMode = .region
            draw([CGPoint(x: 250, y: 30), CGPoint(x: 330, y: 70)])
            expect(canvas.marks.last!.editingHandles.count == 4 && !canvas.marks.last!.isBrushRedaction,
                   "切回框选后可继续绘制可调整四角的遮挡区域")
            canvas.tool = .select
            draw([CGPoint(x: 240, y: 100), CGPoint(x: 255, y: 120)])
            let moved = canvas.marks.first { $0.id == stroke.id }!
            expect(moved.points == points.map { CGPoint(x: $0.x + 15, y: $0.y + 20) }, "选择工具可整体移动涂抹轨迹")
            let movedBitmap = NSBitmapImageRep(cgImage: canvas.renderedImage()!)
            expect(abs(gray(movedBitmap, x: 240, y: 100) - gray(original, x: 240, y: 100)) < 0.01,
                   "移动涂抹后原位置恢复截图内容")
            canvas.deleteSelected()
            expect(canvas.marks.allSatisfy { $0.id != stroke.id } && canvas.marks.count == 2, "删除涂抹不会影响框选区域")
            window.close()
        }
        let editor = EditorController(image: base, size: CGSize(width: 100, height: 100))
        editor.choose(.mosaic)
        func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
        let mode = descendants(editor.window!.contentView!).compactMap { $0 as? NSSegmentedControl }.first!
        mode.selectedSegment = RedactionMode.brush.rawValue
        NSApp.sendAction(mode.action!, to: mode.target, from: mode)
        expect(editor.canvas.redactionMode == .brush, "独立图片编辑器可切换涂抹模式")
        editor.close()
    }
    @MainActor static func selectionBorders(base: CGImage) throws {
        for tool in [MarkTool.rectangle, .blur, .mosaic] {
            let mark = Annotation(tool: tool, points: [CGPoint(x: 30, y: 30), CGPoint(x: 80, y: 80)], color: .systemRed, width: 3)
            for scale in [CGFloat(0.5), 1, 2] {
                expect(mark.selectionPath(scale: scale).bounds == mark.bounds, "\(tool.title)在不同缩放下的选中虚线贴合图形边缘")
            }
            let canvas = CanvasView(base: base, size: CGSize(width: 100, height: 100))
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 100, height: 100), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = canvas
            canvas.tool = tool
            func event(_ type: NSEvent.EventType, x: CGFloat, y: CGFloat) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: canvas.convert(CGPoint(x: x, y: y), to: nil), modifierFlags: [], timestamp: 0,
                                  windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            canvas.mouseDown(with: event(.leftMouseDown, x: 30, y: 30))
            canvas.mouseDragged(with: event(.leftMouseDragged, x: 80, y: 80))
            canvas.mouseUp(with: event(.leftMouseUp, x: 80, y: 80))
            let bitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
            canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
            let exterior = bitmap.colorAt(x: Int(46 * CGFloat(bitmap.pixelsWide) / 100), y: Int(25 * CGFloat(bitmap.pixelsHigh) / 100))!.usingColorSpace(.deviceRGB)!
            expect(exterior.redComponent > 0.95 && exterior.greenComponent > 0.95 && exterior.blueComponent > 0.95,
                   "\(tool.title)外侧不再出现悬空虚线")
            window.close()
        }
    }
}
