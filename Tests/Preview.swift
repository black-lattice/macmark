import AppKit

extension Tests {
    @MainActor static func preview() throws {
        let size = CGSize(width: 920, height: 490)
        let context = CGContext(data: nil, width: 1840, height: 980, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 1840, height: 980))
        context.translateBy(x: 0, y: 980); context.scaleBy(x: 2, y: -2)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        func label(_ text: String, x: CGFloat, y: CGFloat, font: CGFloat = 16, color: NSColor = .darkGray) {
            (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: font), .foregroundColor: color])
        }
        NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
        NSBezierPath(rect: CGRect(x: 0, y: 0, width: 920, height: 70)).fill()
        label("项目工作台", x: 32, y: 22, font: 24)
        label("我的项目    工作记录    设置", x: 540, y: 30)
        label("待处理事项", x: 32, y: 108, font: 22)
        label("今天 · 3 项待处理", x: 32, y: 145, font: 14, color: .gray)
        for (i, text) in ["检查页面列表数据", "更新客户反馈记录", "确认门店报表"].enumerated() {
            let y = CGFloat(210 + i * 74)
            NSColor(calibratedWhite: 0.94, alpha: 1).setStroke()
            let path = NSBezierPath(); path.move(to: CGPoint(x: 32, y: y + 43)); path.line(to: CGPoint(x: 888, y: y + 43)); path.stroke()
            label(text, x: 52, y: y)
            label(i == 0 ? "处理中" : "待确认", x: 760, y: y, color: i == 0 ? .systemBlue : .gray)
        }
        NSGraphicsContext.restoreGraphicsState()
        let base = context.makeImage()!
        let marks = [
            Annotation(tool: .rectangle, points: [CGPoint(x: 42, y: 196), CGPoint(x: 270, y: 240)], color: .systemRed, width: 3),
            Annotation(tool: .arrow, points: [CGPoint(x: 410, y: 180), CGPoint(x: 274, y: 217)], color: .systemRed, width: 3),
            Annotation(tool: .text, points: [CGPoint(x: 410, y: 150)], color: .systemRed, width: 3, text: "请确认这里的数据"),
            Annotation(tool: .line, points: [CGPoint(x: 760, y: 312), CGPoint(x: 816, y: 312)], color: .systemBlue, width: 3)
        ]
        let annotated = Renderer.image(base: base, logicalSize: size, marks: marks)!
        let editor = EditorController(image: annotated, size: size)
        guard let view = editor.window?.contentView else { fatalError("缺少编辑器视图") }
        view.layoutSubtreeIfNeeded()
        expect(view.bounds.width >= 780 && view.bounds.height >= 380, "编辑器布局具有可用空间")
        if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".build/editor-preview.png"))
        }
        editor.close()
        try captureEditing(snapshot: base, size: size)
    }
}
