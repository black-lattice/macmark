import AppKit

extension Tests {
    @MainActor static func arrowRendering() throws {
        let size = CGSize(width: 800, height: 430)
        let context = CGContext(data: nil, width: 1600, height: 860, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 1600, height: 860))
        let base = context.makeImage()!
        let horizontal = Annotation(tool: .arrow, points: [CGPoint(x: 80, y: 200), CGPoint(x: 700, y: 200)], color: .systemRed, width: 3)
        let image = Renderer.image(base: base, logicalSize: size, marks: [horizontal])!
        let bitmap = NSBitmapImageRep(cgImage: image)
        func isRed(x: Int, y: Int) -> Bool {
            let color = bitmap.colorAt(x: x * 2, y: y * 2)!.usingColorSpace(.deviceRGB)!
            return color.redComponent > 0.8 && color.greenComponent < 0.4
        }
        func thickness(at x: Int) -> Int { (160...240).filter { isRed(x: x, y: $0) }.count }
        expect(thickness(at: 120) < thickness(at: 400) && thickness(at: 400) < thickness(at: 650), "箭身由尖细尾部向前逐渐加宽")
        expect(isRed(x: 659, y: 223), "箭头两翼为实心并超出箭身宽度")
        expect(!isRed(x: 100, y: 203) && !isRed(x: 701, y: 200), "箭尾收尖且箭尖不超出指定端点")
        expect(horizontal.contains(CGPoint(x: 659, y: 223)), "点击加宽箭头的两翼可以选中并移动")
        expect(horizontal.bounds.contains(CGPoint(x: 659, y: 223)), "箭头范围包含完整箭翼")
        let short = Annotation(tool: .arrow, points: [CGPoint(x: 20, y: 20), CGPoint(x: 22, y: 20)], color: .systemRed, width: 5)
        expect(short.bounds.minX >= 20 && short.bounds.maxX <= 22, "短箭头自动缩小箭头尺寸，不反向越过尾部")
        let zero = Annotation(tool: .arrow, points: [CGPoint(x: 20, y: 20), CGPoint(x: 20, y: 20)], color: .systemRed, width: 3)
        expect(zero.arrowPath.isEmpty, "零长度箭头不生成无效路径")
        for length in [CGFloat(20), 140, 620] {
            let sizes = [CGFloat(1.5), 3, 5].map {
                Annotation(tool: .arrow, points: [CGPoint(x: 80, y: 200), CGPoint(x: 80 + length, y: 200)], color: .systemRed, width: $0).bounds.height
            }
            expect(sizes[0] < sizes[1] && sizes[1] < sizes[2], "长短箭头的细、中、粗三档均有明显宽度差异")
        }
        var diagonal = horizontal
        diagonal.points = [CGPoint(x: 80, y: 350), CGPoint(x: 700, y: 70)]
        let preview = Renderer.image(base: base, logicalSize: size, marks: [diagonal])!
        try Renderer.png(preview)!.write(to: URL(fileURLWithPath: ".build/tapered-arrow-preview.png"))
        for end in [CGPoint(x: 80, y: 200), CGPoint(x: 400, y: 40), CGPoint(x: 400, y: 360)] {
            let arrow = Annotation(tool: .arrow, points: [CGPoint(x: 400, y: 200), end], color: .systemRed, width: 3)
            let midpoint = CGPoint(x: (400 + end.x) / 2, y: (200 + end.y) / 2)
            expect(arrow.arrowPath.contains(midpoint), "反向或竖向箭头保持正确方向及连续箭身")
        }
    }
}
