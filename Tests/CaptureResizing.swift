import AppKit

extension Tests {
    @MainActor static func captureResizeStability() throws {
        let size = CGSize(width: 800, height: 600)
        for scale in [1, 2] {
            let context = CGContext(data: nil, width: 800 * scale, height: 600 * scale, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(origin: .zero, size: CGSize(width: 800 * scale, height: 600 * scale)))
            context.setFillColor(NSColor.black.cgColor)
            for x in stride(from: 0, to: 800 * scale, by: 4 * scale) {
                context.fill(CGRect(x: x, y: 0, width: scale, height: 600 * scale))
            }
            for y in stride(from: 0, to: 600 * scale, by: 7 * scale) {
                context.fill(CGRect(x: 0, y: y, width: 800 * scale, height: scale))
            }
            let snapshot = context.makeImage()!
            let initial = CGRect(x: 150, y: 120, width: 420, height: 300)
            let pixels = Geometry.cropRect(selection: initial, screenSize: size,
                                           imageSize: CGSize(width: snapshot.width, height: snapshot.height))
            let window = SelectionWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless,
                                         backing: .buffered, defer: false)
            window.contentView = SelectionView(image: snapshot, size: size)
            let editor = EditorController(image: snapshot.cropping(to: pixels)!, size: initial.size,
                                          captureContext: CaptureEditingContext(window: window, snapshot: snapshot, selection: initial))
            let view = window.contentView as! CaptureEditorView
            func event(_ type: NSEvent.EventType, at point: CGPoint) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                                  windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            func interiorPixels() -> [UInt8] {
                let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
                view.cacheDisplay(in: view.bounds, to: bitmap)
                let sx = CGFloat(bitmap.pixelsWide) / size.width, sy = CGFloat(bitmap.pixelsHigh) / size.height
                return (Int(230 * sy)..<Int(270 * sy)).flatMap { y in
                    (Int(300 * sx)..<Int(360 * sx)).map { x in
                        let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                        return UInt8((color.redComponent * 255).rounded())
                    }
                }
            }
            let original = interiorPixels()
            for corner in 0..<4 {
                let start = CaptureSelectionStyle.corners(of: view.selection)[corner]
                let target = view.hitTest(view.convert(start, to: view.superview))!
                expect(target !== editor.canvas && target !== view, "内容稳定性检查通过四角控制点调整选区")
                target.mouseDown(with: event(.leftMouseDown, at: start))
                for distance: CGFloat in [0.25, 0.75, 1.25, 2.5, 7.75] {
                    let point = CGPoint(x: start.x + (corner == 0 || corner == 3 ? -distance : distance),
                                        y: start.y + (corner < 2 ? -distance : distance))
                    target.mouseDragged(with: event(.leftMouseDragged, at: point))
                    let current = interiorPixels()
                    let changed = zip(original, current).filter { abs(Int($0) - Int($1)) > 2 }.count
                    expect(changed == 0, "\(scale)x 截图四角连续调整 \(distance) 点时内容像素保持原位（角 \(corner)）")
                }
                target.mouseUp(with: event(.leftMouseUp, at: start))
            }
            editor.close()
        }
    }
    @MainActor static func captureResizing(snapshot: CGImage, size: CGSize) throws {
        let initial = CGRect(x: 200, y: 140, width: 360, height: 200)
        let pixels = Geometry.cropRect(selection: initial, screenSize: size,
                                       imageSize: CGSize(width: snapshot.width, height: snapshot.height))
        let window = SelectionWindow(contentRect: CGRect(x: -size.width, y: 40, width: size.width, height: size.height),
                                     styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = SelectionView(image: snapshot, size: size)
        let editor = EditorController(image: snapshot.cropping(to: pixels)!, size: initial.size,
                                      captureContext: CaptureEditingContext(window: window, snapshot: snapshot, selection: initial))
        let canvas = editor.canvas
        let view = window.contentView as! CaptureEditorView
        let originalWindow = window.frame
        let toolbar = view.subviews.compactMap { $0 as? CaptureToolbarView }.first!
        func settle() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01)) }
        func event(_ type: NSEvent.EventType, at point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                              windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func screenPoints(_ mark: Annotation) -> [CGPoint] {
            mark.points.map { CGPoint(x: $0.x + view.selection.minX, y: $0.y + view.selection.minY) }
        }
        func draw(_ tool: MarkTool, from start: CGPoint, to end: CGPoint) {
            editor.choose(tool)
            let origin = view.selection.origin
            canvas.mouseDown(with: event(.leftMouseDown, at: CGPoint(x: origin.x + start.x, y: origin.y + start.y)))
            canvas.mouseDragged(with: event(.leftMouseDragged, at: CGPoint(x: origin.x + end.x, y: origin.y + end.y)))
            canvas.mouseUp(with: event(.leftMouseUp, at: CGPoint(x: origin.x + end.x, y: origin.y + end.y)))
            settle()
        }
        func drag(_ corner: Int, by delta: CGPoint, inset: CGPoint = .zero) {
            let handle = CaptureSelectionStyle.corners(of: view.selection)[corner]
            let start = CGPoint(x: handle.x + inset.x, y: handle.y + inset.y)
            let end = CGPoint(x: start.x + delta.x, y: start.y + delta.y)
            let target = view.hitTest(view.convert(start, to: view.superview))!
            expect(target !== canvas && target !== view && target !== toolbar, "选区角点优先接收拖拽，不触发标注或工具栏")
            target.mouseDown(with: event(.leftMouseDown, at: start))
            let cursor = NSCursor.current
            expect(cursor === AnnotationCursor.resize(corner: corner), "选区角点显示对应斜向调整光标")
            settle()
            target.mouseDragged(with: event(.leftMouseDragged, at: CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)))
            target.mouseDragged(with: event(.leftMouseDragged, at: end))
            expect(NSCursor.current === cursor, "调整选区过程中保持斜向光标")
            target.mouseUp(with: event(.leftMouseUp, at: end))
            settle()
        }
        draw(.line, from: CGPoint(x: 50, y: 40), to: CGPoint(x: 130, y: 40))
        let originalLine = screenPoints(canvas.marks[0])
        let originalExport = NSBitmapImageRep(cgImage: canvas.renderedImage()!)
        let lineColor = originalExport.colorAt(x: Int(90 * CGFloat(originalExport.pixelsWide) / initial.width),
                                              y: Int(40 * CGFloat(originalExport.pixelsHigh) / initial.height))!.usingColorSpace(.deviceRGB)!
        for corner in 0..<4 {
            let before = view.selection
            let anchor = CaptureSelectionStyle.corners(of: before)[(corner + 2) % 4]
            let delta = CGPoint(x: corner == 0 || corner == 3 ? -40 : 40, y: corner < 2 ? -30 : 30)
            drag(corner, by: delta, inset: CGPoint(x: 2, y: 2))
            let resized = view.selection
            expect(resized.width == before.width + 40 && resized.height == before.height + 30, "四角均可扩大截图宽高，点击偏移不导致边框跳动")
            expect(CaptureSelectionStyle.corners(of: resized)[(corner + 2) % 4] == anchor, "调整截图固定对角位置")
            expect(window.frame == originalWindow && canvas.frame == resized && canvas.logicalSize == resized.size && canvas.scale == 1,
                   "调整选区保持原窗口与一比一标注比例，支持负坐标显示器")
            expect(screenPoints(canvas.marks[0]) == originalLine, "调整选区不移动或缩放已有标注")
            expect(toolbar.frame.midX == resized.midX && view.bounds.contains(toolbar.frame), "工具栏跟随调整后的选区居中并避免越界")
            let exported = canvas.renderedImage()!
            let crop = Geometry.cropRect(selection: resized, screenSize: size, imageSize: CGSize(width: snapshot.width, height: snapshot.height))
            expect(exported.width == Int(crop.width) && exported.height == Int(crop.height), "调整后导出采用新的截图像素宽高")
            let bitmap = NSBitmapImageRep(cgImage: exported)
            let source = NSBitmapImageRep(cgImage: snapshot)
            let revealed = bitmap.colorAt(x: 10, y: 10)!.usingColorSpace(.deviceRGB)!
            let expected = source.colorAt(x: Int(crop.minX) + 10, y: Int(crop.minY) + 10)!.usingColorSpace(.deviceRGB)!
            expect(abs(revealed.redComponent - expected.redComponent) < 0.02 && abs(revealed.greenComponent - expected.greenComponent) < 0.02,
                   "扩大选区从原始截图恢复新增区域的真实画面")
            let linePixel = bitmap.colorAt(x: Int((originalLine[0].x + 40 - resized.minX) * CGFloat(exported.width) / resized.width),
                                           y: Int((originalLine[0].y - resized.minY) * CGFloat(exported.height) / resized.height))!.usingColorSpace(.deviceRGB)!
            expect(abs(linePixel.redComponent - lineColor.redComponent) < 0.03 && abs(linePixel.greenComponent - lineColor.greenComponent) < 0.03
                && abs(linePixel.blueComponent - lineColor.blueComponent) < 0.03, "调整后导出的标注仍对齐原屏幕位置")
            canvas.undo(); settle()
            expect(view.selection == before && screenPoints(canvas.marks[0]) == originalLine, "一次撤销恢复整个选区拖拽及标注坐标")
            canvas.redo(); settle()
            expect(view.selection == resized && screenPoints(canvas.marks[0]) == originalLine, "重做恢复选区调整")
            canvas.undo(); settle()
        }
        canvas.undo(); settle()
        expect(canvas.marks.isEmpty && view.selection == initial, "撤销选区后仍可独立撤销此前标注")
        canvas.redo(); settle()
        expect(screenPoints(canvas.marks[0]) == originalLine, "重做此前标注保持原坐标")

        draw(.blur, from: CGPoint(x: 20, y: 60), to: CGPoint(x: 140, y: 100))
        canvas.redactionMode = .brush
        draw(.mosaic, from: CGPoint(x: 40, y: 145), to: CGPoint(x: 110, y: 145))
        editor.choose(.text)
        canvas.mouseDown(with: event(.leftMouseDown, at: CGPoint(x: initial.minX + 180, y: initial.minY + 115)))
        let textEditor = canvas.subviews.compactMap { $0 as? AnnotationTextEditor }.first!
        textEditor.textView.string = "调整截图"
        let oldPoints = canvas.marks.map(screenPoints)
        drag(0, by: CGPoint(x: -40, y: -30))
        expect(canvas.marks.count == 4 && !canvas.subviews.contains(where: { $0 is AnnotationTextEditor }), "调整前提交正在输入的文字")
        expect(Array(canvas.marks.prefix(3)).map(screenPoints) == oldPoints && canvas.marks[3].points[0] == CGPoint(x: 220, y: 145),
               "线条、模糊、涂抹与文字均保持屏幕位置")
        if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let exported = NSBitmapImageRep(cgImage: canvas.renderedImage()!)
            for point in [CGPoint(x: initial.minX + 80, y: initial.minY + 80), CGPoint(x: initial.minX + 70, y: initial.minY + 145)] {
                let preview = bitmap.colorAt(x: Int(point.x * CGFloat(bitmap.pixelsWide) / size.width),
                                             y: Int(point.y * CGFloat(bitmap.pixelsHigh) / size.height))!.usingColorSpace(.deviceRGB)!
                let output = exported.colorAt(x: Int((point.x - view.selection.minX) * CGFloat(exported.pixelsWide) / canvas.logicalSize.width),
                                              y: Int((point.y - view.selection.minY) * CGFloat(exported.pixelsHigh) / canvas.logicalSize.height))!.usingColorSpace(.deviceRGB)!
                expect(abs(preview.redComponent - output.redComponent) < 0.06 && abs(preview.greenComponent - output.greenComponent) < 0.06,
                       "调整后的遮挡预览与导出一致")
            }
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".build/capture-resize-preview-\(snapshot.width).png"))
        }
        canvas.undo(); settle()
        expect(view.selection == initial && canvas.marks.count == 4 && canvas.marks[3].points[0] == CGPoint(x: 180, y: 115),
               "撤销调整后保留已提交文字并还原坐标")
        canvas.undo(); settle()
        expect(canvas.marks.count == 3, "调整选区与文字提交使用独立撤销步骤")

        drag(2, by: CGPoint(x: size.width, y: size.height))
        expect(view.selection.maxX == size.width && view.selection.maxY == size.height, "扩大选区限制在原显示器范围内")
        drag(0, by: CGPoint(x: -size.width, y: -size.height))
        expect(view.selection == view.bounds, "可将截图扩大到整个原始屏幕")
        expect(canvas.base.width == snapshot.width && canvas.base.height == snapshot.height, "全屏扩大保留完整原始像素")
        drag(0, by: CGPoint(x: size.width * 2, y: size.height * 2), inset: CGPoint(x: 1, y: 1))
        expect(view.selection.width == 2 && view.selection.height == 2 && view.selection.maxX == size.width && view.selection.maxY == size.height,
               "缩小到最小选区时固定对角，不产生零尺寸或越界")
        canvas.undo(); settle()
        expect(view.selection == view.bounds && canvas.marks.count == 3, "缩小后重新扩大可恢复区域外的已有标注")
        canvas.undo(); settle()
        let expectedFrame = window.convertToScreen(canvas.convert(canvas.bounds, to: nil))
        var pinned = false
        editor.onPin = { image, logicalSize, frame in
            pinned = image.width == canvas.base.width && image.height == canvas.base.height
                && logicalSize == view.selection.size && frame == expectedFrame
        }
        editor.pinImage()
        expect(pinned && !window.isVisible, "锚定使用调整后的图片、尺寸与屏幕位置")
    }
}
