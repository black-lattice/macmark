import AppKit

@MainActor private final class DeferredTextCaptureRecognizer: PinnedTextRecognizing {
    var requests: [CheckedContinuation<PinnedTextRecognition, Error>] = []
    func recognize(_ image: CGImage) async throws -> PinnedTextRecognition {
        try await withCheckedThrowingContinuation { requests.append($0) }
    }
}

extension Tests {
    @MainActor static func directTextCapture(base: CGImage) throws {
        var finished = false
        let task = Task { @MainActor in
            let source = DeferredTextCaptureRecognizer()
            let controller = TextCaptureController(recognizer: source)
            @MainActor func waitUntil(_ condition: @MainActor () -> Bool) async {
                let deadline = Date(timeIntervalSinceNow: 5)
                while !condition() && Date() < deadline { await Task.yield() }
                expect(condition(), "直接文字提取异步状态及时更新")
            }
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString("original", forType: .string)
            controller.recognize(base)
            await waitUntil { source.requests.count == 1 }
            expect(controller.state == .recognizing && controller.window!.isVisible, "OCR 显示识别状态和可取消窗口")
            controller.cancel()
            source.requests[0].resume(returning: PinnedTextRecognition(text: "late result", analysis: nil))
            await Task.yield()
            expect(controller.state == .cancelled && NSPasteboard.general.string(forType: .string) == "original",
                   "取消 OCR 后迟到的结果不会覆盖剪贴板")
            controller.recognize(base)
            await waitUntil { source.requests.count == 2 }
            source.requests[1].resume(returning: PinnedTextRecognition(text: " \n截图文字 2026\n ", analysis: nil))
            await waitUntil { controller.state == .copied }
            expect(NSPasteboard.general.string(forType: .string) == "截图文字 2026", "直接 OCR 去除首尾空白并复制识别文字")
            controller.recognize(base)
            await waitUntil { source.requests.count == 3 }
            source.requests[2].resume(returning: PinnedTextRecognition(text: " \n ", analysis: nil))
            await waitUntil { controller.state == .empty }
            expect(NSPasteboard.general.string(forType: .string) == "截图文字 2026", "空识别结果保留原剪贴板")
            controller.recognize(base)
            await waitUntil { source.requests.count == 4 }
            source.requests[3].resume(throwing: CocoaError(.fileReadUnknown))
            await waitUntil { controller.state == .failed }
            expect(controller.window!.isVisible, "OCR 失败提示保留到用户关闭")
            controller.recognize(base)
            await waitUntil { source.requests.count == 5 }
            controller.recognize(base)
            await waitUntil { source.requests.count == 6 }
            source.requests[4].resume(returning: PinnedTextRecognition(text: "stale", analysis: nil))
            source.requests[5].resume(returning: PinnedTextRecognition(text: "newest", analysis: nil))
            await waitUntil { controller.state == .copied }
            expect(NSPasteboard.general.string(forType: .string) == "newest", "重复发起 OCR 仅采用最新请求")
            controller.close()
            finished = true
        }
        let deadline = Date(timeIntervalSinceNow: 30)
        while !finished && Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01)) }
        if !finished { task.cancel() }
        expect(finished, "直接 OCR 生命周期测试完成")
        let domain = "TextShortcutTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        CaptureShortcut.defaultValue.save(to: defaults)
        CaptureShortcut.textDefaultValue.save(to: defaults, key: CaptureShortcut.textStorageKey)
        expect(CaptureShortcut.load(from: defaults) == .defaultValue
               && CaptureShortcut.load(from: defaults, key: CaptureShortcut.textStorageKey, fallback: .textDefaultValue) == .textDefaultValue,
               "截图和 OCR 快捷键独立保存、恢复")
        let settings = ShortcutSettingsController(shortcut: .defaultValue, purpose: "提取文字", defaultShortcut: .textDefaultValue)
        func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
        descendants(settings.window!.contentView!).compactMap { $0 as? NSButton }.first { $0.title == "恢复默认" }!.performClick(nil)
        expect(settings.recorder.shortcut == .textDefaultValue, "OCR 设置恢复自己的默认快捷键")
        settings.close()
    }
}
