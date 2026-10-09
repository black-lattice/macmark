import AppKit

extension Tests {
    @MainActor static func redactionRendering() throws {
        let size = CGSize(width: 400, height: 240)
        let context = CGContext(data: nil, width: 800, height: 480, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.translateBy(x: 0, y: 480); context.scaleBy(x: 2, y: -2)
        for y in stride(from: 0, to: 240, by: 4) {
            for x in stride(from: 0, to: 400, by: 4) {
                let shade: CGFloat = (x / 4 + y / 4) % 2 == 0 ? 0.5 : 0
                context.setFillColor(NSColor(calibratedRed: CGFloat(x) / 1600 + shade, green: 0.2 + shade,
                                             blue: CGFloat(y) / 960 + shade, alpha: 1).cgColor)
                context.fill(CGRect(x: x, y: y, width: 4, height: 4))
            }
        }
        let base = context.makeImage()!
        let original = NSBitmapImageRep(cgImage: base)
        func color(_ bitmap: NSBitmapImageRep, x: Int, y: Int) -> NSColor {
            bitmap.colorAt(x: x * 2, y: y * 2)!.usingColorSpace(.deviceRGB)!
        }
        func difference(_ a: NSColor, _ b: NSColor) -> CGFloat {
            max(abs(a.redComponent - b.redComponent), abs(a.greenComponent - b.greenComponent), abs(a.blueComponent - b.blueComponent))
        }
        for tool in [MarkTool.blur, .mosaic] {
            let mark = Annotation(tool: tool, points: [CGPoint(x: 48, y: 32), CGPoint(x: 208, y: 184)], color: .systemRed, width: 3)
            let image = Renderer.image(base: base, logicalSize: size, marks: [mark])!
            let bitmap = NSBitmapImageRep(cgImage: image)
            expect(image.width == 800 && image.height == 480, "\(tool.title)导出保留 Retina 像素尺寸")
            expect(difference(color(bitmap, x: 30, y: 200), color(original, x: 30, y: 200)) < 0.01,
                   "\(tool.title)不改变框选区域外的截图")
            expect(difference(color(original, x: 88, y: 92), color(original, x: 92, y: 92)) > 0.4,
                   "测试截图具有可验证的细节纹理")
            let delta = difference(color(bitmap, x: 88, y: 92), color(bitmap, x: 92, y: 92))
            expect(delta < (tool == .mosaic ? 0.01 : 0.1), "\(tool.title)实际隐藏区域内的细节")
            expect(color(bitmap, x: 120, y: 172).blueComponent > color(bitmap, x: 120, y: 60).blueComponent + 0.08,
                   "\(tool.title)区域上下方向保持正确")
            expect(mark.contains(CGPoint(x: 120, y: 100)), "遮挡区域内部支持选择和整体移动")
            let canvas = CanvasView(base: base, size: size)
            canvas.tool = tool
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = canvas
            func event(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                                  windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            canvas.mouseDown(with: event(.leftMouseDown, mark.points[0]))
            canvas.mouseDragged(with: event(.leftMouseDragged, mark.points[1]))
            canvas.mouseUp(with: event(.leftMouseUp, mark.points[1]))
            let preview = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
            canvas.cacheDisplay(in: canvas.bounds, to: preview)
            let sample = preview.colorAt(x: Int(120 * CGFloat(preview.pixelsWide) / size.width),
                                         y: Int(100 * CGFloat(preview.pixelsHigh) / size.height))!.usingColorSpace(.deviceRGB)!
            expect(difference(sample, color(bitmap, x: 120, y: 100)) < 0.04, "\(tool.title)画布预览与导出效果一致")
            try Renderer.png(image)!.write(to: URL(fileURLWithPath: ".build/\(tool.rawValue)-preview.png"))
            var outside = mark
            outside.points = [CGPoint(x: -10, y: -10), CGPoint(x: 40, y: 40)]
            let clipped = Renderer.image(base: base, logicalSize: size, marks: [outside])!
            expect(clipped.width == base.width && clipped.height == base.height, "边缘遮挡区域裁剪后仍可正常导出")
            canvas.tool = .select
            canvas.mouseDown(with: event(.leftMouseDown, CGPoint(x: 120, y: 100)))
            canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: 120, y: 100)))
            canvas.deleteSelected()
            expect(canvas.marks.isEmpty, "\(tool.title)区域可以删除")
            window.close()
        }
    }
}
