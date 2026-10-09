import AppKit

extension Tests {
    @MainActor static func textAppearance() throws {
        let size = CGSize(width: 300, height: 200)
        let context = CGContext(data: nil, width: 600, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 600, height: 400))
        for scale in [CGFloat(0.5), 1, 2] {
            let canvas = CanvasView(base: context.makeImage()!, size: size)
            let frame = CGRect(x: 100, y: 100, width: size.width * scale, height: size.height * scale)
            let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = canvas
            canvas.setFrameSize(frame.size); canvas.tool = .text
            let point = CGPoint(x: 20, y: 20)
            let down = NSEvent.mouseEvent(with: .leftMouseDown, location: canvas.convert(CGPoint(x: point.x * scale, y: point.y * scale), to: nil),
                                         modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                         eventNumber: 0, clickCount: 1, pressure: 1)!
            canvas.mouseDown(with: down)
            let editor = canvas.subviews.compactMap { $0 as? AnnotationTextEditor }.first!
            editor.textView.insertText("第一行 ABC\n  第二行 xyz", replacementRange: NSRange(location: NSNotFound, length: 0))
            window.makeFirstResponder(canvas)
            func snapshot() -> NSBitmapImageRep {
                canvas.layoutSubtreeIfNeeded()
                let bitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
                canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
                return bitmap
            }
            let before = snapshot()
            let enter = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                         windowNumber: window.windowNumber, context: nil, characters: "\r",
                                         charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
            editor.textView.keyDown(with: enter)
            let after = snapshot()
            var changed = 0
            for y in 0..<before.pixelsHigh {
                for x in 0..<before.pixelsWide {
                    if before.colorAt(x: x, y: y) != after.colorAt(x: x, y: y) { changed += 1 }
                }
            }
            try before.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".build/text-input-\(scale).png"))
            try after.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".build/text-confirmed-\(scale).png"))
            print("文字前后差异，缩放 \(scale)：\(changed) 像素")
            expect(changed == 0, "缩放 \(scale) 时输入文字与确认后像素一致")
            expect(canvas.marks.last!.points[0] == point, "透明输入保留截图点击坐标")
            window.close()
        }
    }
}
