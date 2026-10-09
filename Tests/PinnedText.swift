import AppKit
import VisionKit

@MainActor private final class DeferredPinnedTextRecognizer: PinnedTextRecognizing {
    var requests: [CheckedContinuation<PinnedTextRecognition, Error>] = []
    func recognize(_ image: CGImage) async throws -> PinnedTextRecognition {
        try await withCheckedThrowingContinuation { requests.append($0) }
    }
}

extension Tests {
    @MainActor static func pinnedTextWithRunLoop() throws {
        let originalPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.accessory)
        defer { NSApp.setActivationPolicy(originalPolicy) }
        var finished = false
        var failure: Error?
        let task = Task { @MainActor in
            do { try await pinnedText() }
            catch { failure = error }
            finished = true
        }
        let deadline = Date(timeIntervalSinceNow: 45)
        while !finished && Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01)) }
        if !finished { task.cancel() }
        expect(finished, "锚定文字识别与选择检查完成")
        if let failure { throw failure }
    }

    @MainActor private static func pinnedText() async throws {
        let context = CGContext(data: nil, width: 1200, height: 500, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 1200, height: 500))
        context.translateBy(x: 0, y: 500); context.scaleBy(x: 2, y: -2)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        for (text, y) in [("Hello MacMark 2026", CGFloat(30)), ("截图文字复制测试", CGFloat(100))] {
            (text as NSString).draw(at: CGPoint(x: 30, y: y), withAttributes: [
                .font: NSFont.systemFont(ofSize: 30), .foregroundColor: NSColor.black
            ])
        }
        NSGraphicsContext.restoreGraphicsState()
        let image = context.makeImage()!
        let fallback = try await PinnedTextRecognizer(useLiveText: false).recognize(image)
        expect(fallback.text.contains("Hello MacMark 2026") && fallback.text.contains("截图文字复制测试"),
               "普通 OCR 在原始 Retina 图像上识别中英文文字")
        expect(fallback.analysis == nil, "不支持实况文本时仍能取得可复制的文字")

        let source = DeferredPinnedTextRecognizer()
        let controller = PinnedScreenshotController(image: image, frame: CGRect(x: 100, y: 100, width: 600, height: 250), recognizer: source)
        let panel = controller.window!
        panel.orderFrontRegardless()
        let view = panel.contentView as! PinnedScreenshotView
        func event(_ type: NSEvent.EventType, at point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                              windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func menu() -> NSMenu { view.menu(for: event(.rightMouseDown, at: CGPoint(x: 550, y: 200)))! }
        func waitUntil(_ message: String = "异步文字识别状态及时更新", _ condition: () -> Bool) async {
            let deadline = Date(timeIntervalSinceNow: 5)
            while !condition() && Date() < deadline { await Task.yield() }
            expect(condition(), message)
        }
        await waitUntil { source.requests.count == 1 }
        expect(view.recognitionState == .recognizing && menu().item(withTitle: "正在识别文字…") != nil
               && !menu().item(withTitle: "复制全部文字")!.isEnabled, "识别期间显示状态，暂不允许复制空文字")
        expect(view.hitTest(view.convert(CGPoint(x: 550, y: 200), to: view.superview)) === view,
               "文字识别不阻挡空白区域移动截图")
        source.requests[0].resume(returning: fallback)
        await waitUntil { view.recognitionState == .ready }
        let copyAll = menu().item(withTitle: "复制全部文字")!
        expect(copyAll.isEnabled, "普通 OCR 识别完成后启用右键复制全部文字")
        NSApp.sendAction(copyAll.action!, to: copyAll.target, from: copyAll)
        expect(NSPasteboard.general.string(forType: .string) == fallback.text, "右键复制全部文字写入纯文字剪贴板")
        let origin = panel.frame.origin
        view.mouseDown(with: event(.leftMouseDown, at: CGPoint(x: 550, y: 200)))
        view.mouseDragged(with: event(.leftMouseDragged, at: CGPoint(x: 580, y: 210)))
        view.mouseUp(with: event(.leftMouseUp, at: CGPoint(x: 550, y: 200)))
        expect(panel.frame.origin == CGPoint(x: origin.x + 30, y: origin.y - 10), "识别完成后仍能拖动空白区域移动截图")
        view.startRecognition()
        await waitUntil { source.requests.count == 2 }
        source.requests[1].resume(throwing: NSError(domain: "test-ocr", code: 1))
        await waitUntil { view.recognitionState == .failed }
        let retry = menu().item(withTitle: "重新识别文字")!
        expect(menu().item(withTitle: "文字识别失败") != nil, "识别失败后提供状态和重试菜单")
        NSApp.sendAction(retry.action!, to: retry.target, from: retry)
        await waitUntil { source.requests.count == 3 }
        source.requests[2].resume(returning: PinnedTextRecognition(text: "  \n", analysis: nil))
        await waitUntil { view.recognitionState == .empty }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("保留原剪贴板", forType: .string)
        view.copyAllText(nil)
        expect(menu().item(withTitle: "未识别到文字") != nil && !menu().item(withTitle: "复制全部文字")!.isEnabled
               && NSPasteboard.general.string(forType: .string) == "保留原剪贴板", "无文字时保留剪贴板并明确提示")
        view.startRecognition()
        await waitUntil { source.requests.count == 4 }
        view.startRecognition()
        await waitUntil { source.requests.count == 5 }
        source.requests[3].resume(returning: fallback)
        for _ in 0..<10 { await Task.yield() }
        expect(view.recognitionState == .recognizing && view.recognizedText.isEmpty, "重试后忽略旧识别任务的迟到结果")
        controller.close()
        source.requests[4].resume(returning: fallback)
        for _ in 0..<10 { await Task.yield() }
        expect(view.recognitionState == .stopped && view.recognizedText.isEmpty && !panel.isVisible,
               "销毁锚定窗口后取消识别并忽略迟到结果")

        if ImageAnalyzer.isSupported {
            let result = try await PinnedTextRecognizer().recognize(image)
            expect(result.analysis != nil && result.text.contains("Hello"), "支持设备使用系统实况文本识别")
            let nativeSource = DeferredPinnedTextRecognizer()
            let native = PinnedScreenshotController(image: image, frame: CGRect(x: 100, y: 100, width: 600, height: 250), recognizer: nativeSource)
            defer { native.close() }
            let nativeView = native.window!.contentView as! PinnedScreenshotView
            native.window?.orderFrontRegardless()
            await waitUntil { !nativeSource.requests.isEmpty }
            nativeSource.requests[0].resume(returning: result)
            await waitUntil { nativeView.recognitionState == .ready }
            let overlay = nativeView.textOverlay
            expect(overlay.frame == nativeView.bounds && overlay.trackingImageView?.frame == nativeView.bounds,
                   "实况文本覆盖层与缩放后的截图保持对齐")
            nativeView.layoutSubtreeIfNeeded()
            overlay.setContentsRectNeedsUpdate()
            var textPoint: CGPoint?
            for y in stride(from: CGFloat(30), through: 65, by: 5) {
                for x in stride(from: CGFloat(30), through: 160, by: 5) {
                    let point = CGPoint(x: x, y: y)
                    if overlay.hasText(at: point) { textPoint = point; break }
                }
                if textPoint != nil { break }
            }
            expect(textPoint != nil, "Retina 缩放后的文字区域正确命中系统文字选择")
            let target = nativeView.hitTest(nativeView.convert(textPoint!, to: nativeView.superview))!
            expect(target !== nativeView, "点击文字交给实况文本，空白处保留窗口拖动")
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let click = NSEvent.mouseEvent(with: type, location: nativeView.convert(textPoint!, to: nil),
                                               modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: native.window!.windowNumber, context: nil, eventNumber: 0,
                                               clickCount: 2, pressure: 1)!
                native.window!.sendEvent(click)
            }
            await waitUntil("双击文字后形成系统文字选区") { !nativeView.selectedText.isEmpty }
            expect(native.window!.isKeyWindow, "直接点击文字可在非激活锚定窗口中选择并接收复制快捷键")
            let text = overlay.text
            let start = text.range(of: "Hello")!.lowerBound
            let end = text.index(start, offsetBy: 5)
            overlay.selectedRanges = [start..<end]
            await waitUntil { nativeView.selectedText == "Hello" }
            native.copySelectedText()
            expect(NSPasteboard.general.string(forType: .string) == "Hello", "系统选区只复制选中的文字")
            let commandC = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0,
                                           windowNumber: native.window!.windowNumber, context: nil, characters: "c",
                                           charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8)!
            NSPasteboard.general.clearContents()
            expect(native.window!.performKeyEquivalent(with: commandC)
                   && NSPasteboard.general.string(forType: .string) == "Hello", "锚定窗口的 Command C 复制文字选区")
            let nativeMenu = nativeView.overlayView(overlay, updatedMenuFor: NSMenu(),
                                                    for: event(.rightMouseDown, at: .zero), at: .zero)
            expect(nativeMenu.item(withTitle: "复制全部文字") != nil && nativeMenu.item(withTitle: "销毁锚定截图") != nil,
                   "系统文字菜单同时保留复制全部文字和销毁锚定截图")
            if let bitmap = nativeView.bitmapImageRepForCachingDisplay(in: nativeView.bounds) {
                nativeView.cacheDisplay(in: nativeView.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".build/pinned-text-preview.png"))
            }
            nativeView.mouseDown(with: event(.leftMouseDown, at: CGPoint(x: 550, y: 200)))
            nativeView.mouseUp(with: event(.leftMouseUp, at: CGPoint(x: 550, y: 200)))
            expect(!overlay.hasActiveTextSelection, "拖动空白区域时清除文字选择")
        }
    }
}
