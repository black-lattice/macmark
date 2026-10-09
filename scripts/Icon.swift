import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: CGFloat(pixels) / 512, y: CGFloat(pixels) / 512)
        context.setFillColor(NSColor(calibratedRed: 0.05, green: 0.50, blue: 0.46, alpha: 1).cgColor)
        context.addPath(CGPath(roundedRect: CGRect(x: 20, y: 20, width: 472, height: 472), cornerWidth: 108,
                               cornerHeight: 108, transform: nil)); context.fillPath()
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(24); context.setLineCap(.round); context.setLineJoin(.round)
        for corner in [CGPoint(x: 136, y: 376), CGPoint(x: 376, y: 376),
                       CGPoint(x: 136, y: 136), CGPoint(x: 376, y: 136)] {
            let dx: CGFloat = corner.x < 256 ? 1 : -1
            let dy: CGFloat = corner.y < 256 ? 1 : -1
            context.move(to: CGPoint(x: corner.x + dx * 62, y: corner.y))
            context.addLine(to: corner)
            context.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * 62))
            context.strokePath()
        }
        context.setStrokeColor(NSColor.white.cgColor)
        context.move(to: CGPoint(x: 200, y: 200)); context.addLine(to: CGPoint(x: 320, y: 320)); context.strokePath()
        context.setFillColor(NSColor.white.cgColor)
        context.move(to: CGPoint(x: 325, y: 325)); context.addLine(to: CGPoint(x: 246, y: 308))
        context.addLine(to: CGPoint(x: 308, y: 246)); context.closePath(); context.fillPath()
        let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try rep.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
    }
}
