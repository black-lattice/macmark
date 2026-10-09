import AppKit

@MainActor private final class DeferredCaptureSource: CaptureImageSource {
    struct Request {
        let displays: [CaptureDisplay]
        let receive: (CaptureDisplay, CGImage) -> Void
        let continuation: CheckedContinuation<Void, Error>
    }
    var prepared = false
    var requests: [Request] = []
    func prepare() { prepared = true }
    func capture(_ displays: [CaptureDisplay], receive: @escaping (CaptureDisplay, CGImage) -> Void) async throws {
        try await withCheckedThrowingContinuation { continuation in
            requests.append(Request(displays: displays, receive: receive, continuation: continuation))
        }
    }
}

extension Tests {
    @MainActor static func capturePreparationWithRunLoop(base: CGImage) throws {
        var finished = false
        var failure: Error?
        Task { @MainActor in
            do { try await capturePreparation(base: base) }
            catch { failure = error }
            finished = true
        }
        let deadline = Date(timeIntervalSinceNow: 5)
        while !finished && Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01)) }
        expect(finished, "异步截图衔接检查在 AppKit 主线程运行循环中完成")
        if let failure { throw failure }
    }
    @MainActor static func capturePreparation(base: CGImage) async throws {
        let left = CaptureDisplay(id: 1, frame: CGRect(x: -400, y: 0, width: 400, height: 240), pixelSize: CGSize(width: 800, height: 480))
        let right = CaptureDisplay(id: 2, frame: CGRect(x: 0, y: 0, width: 400, height: 240), pixelSize: CGSize(width: 800, height: 480))
        let source = DeferredCaptureSource()
        let capture = CaptureCoordinator(source: source, hasAccess: { true }, displays: { [left, right] })
        var delivered: CaptureEditingContext?
        var cropped: CGImage?
        var errors: [String] = []
        capture.onCapture = { image, _, context in delivered = context; cropped = image }
        capture.onError = { errors.append($0) }
        capture.prepare()
        expect(source.prepared, "启动阶段预备截图元数据")
        capture.start()
        expect(capture.overlays.count == 2 && capture.overlays.allSatisfy(\.isVisible) && source.requests.isEmpty,
               "不等待异步截图任务，触发时立即显示全部可操作选区")
        expect(capture.overlays.contains(where: \.isKeyWindow), "准备阶段已有选区接收键盘取消操作")
        capture.start()
        expect(capture.overlays.count == 2, "截图准备过程中重复触发不会创建重复选区")
        while source.requests.isEmpty { await Task.yield() }
        let first = capture.overlays[0]
        let view = first.contentView as! SelectionView
        func event(_ type: NSEvent.EventType, view: NSView, x: CGFloat, y: CGFloat) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: view.convert(CGPoint(x: x, y: y), to: nil), modifierFlags: [], timestamp: 0,
                              windowNumber: view.window!.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        view.mouseDown(with: event(.leftMouseDown, view: view, x: 20, y: 20))
        view.mouseDragged(with: event(.leftMouseDragged, view: view, x: 100, y: 80))
        view.mouseUp(with: event(.leftMouseUp, view: view, x: 100, y: 80))
        expect(delivered == nil && capture.busy, "画面未就绪时也能完成框选并保留操作")
        let secondary = capture.overlays[1]
        source.requests[0].receive(left, base)
        expect(delivered?.selection == CGRect(x: 20, y: 20, width: 80, height: 60) && delivered?.window === first,
               "当前屏幕画面就绪后立即沿用原窗口进入编辑")
        expect(!secondary.isVisible && capture.overlays.isEmpty && capture.busy,
               "无需等待另一块屏幕，关闭其他选区并保持编辑会话")
        let expected = Geometry.cropRect(selection: delivered!.selection, screenSize: left.frame.size,
                                        imageSize: CGSize(width: base.width, height: base.height))
        expect(cropped!.width == Int(expected.width) && cropped!.height == Int(expected.height), "提前框选仍按实际图像像素正确裁剪")
        source.requests[0].receive(right, base)
        expect(delivered?.window === first && capture.overlays.isEmpty, "进入编辑后的迟到屏幕结果不会重新显示选区")
        source.requests[0].continuation.resume()
        first.close(); capture.cancel()
        expect(!capture.busy, "结束编辑后可再次触发截图")
        delivered = nil
        capture.start()
        while source.requests.count < 2 { await Task.yield() }
        let cancelled = capture.overlays
        let cancelledView = cancelled[0].contentView as! SelectionView
        cancelledView.rightMouseDown(with: event(.rightMouseDown, view: cancelledView, x: 20, y: 20))
        expect(!capture.busy && cancelled.allSatisfy { !$0.isVisible }, "截图准备时右键可以立即取消")
        capture.start()
        while source.requests.count < 3 { await Task.yield() }
        let replacement = capture.overlays
        source.requests[1].receive(left, base)
        source.requests[1].continuation.resume(throwing: NSError(domain: "cancelled-old-capture", code: 1))
        await Task.yield()
        expect(errors.isEmpty && capture.overlays.first === replacement.first && capture.busy,
               "旧截图任务的迟到画面和错误不会干扰新会话")
        source.requests[2].receive(left, base)
        let readyView = replacement[0].contentView as! SelectionView
        readyView.mouseDown(with: event(.leftMouseDown, view: readyView, x: 30, y: 40))
        readyView.mouseUp(with: event(.leftMouseUp, view: readyView, x: 130, y: 100))
        expect(delivered?.selection == CGRect(x: 30, y: 40, width: 100, height: 60), "画面先就绪时保持原有框选交互")
        source.requests[2].continuation.resume()
        delivered?.window.close(); capture.cancel()
        capture.start()
        while source.requests.count < 4 { await Task.yield() }
        let escapeWindow = capture.overlays[0]
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                      windowNumber: escapeWindow.windowNumber, context: nil, characters: "\u{1b}",
                                      charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        (escapeWindow.contentView as! SelectionView).keyDown(with: escape)
        expect(!capture.busy && capture.overlays.isEmpty, "截图准备时 Escape 可以立即取消")
        source.requests[3].continuation.resume()
        let failingSource = DeferredCaptureSource()
        let failing = CaptureCoordinator(source: failingSource, hasAccess: { true }, displays: { [right] })
        failing.onError = { errors.append($0) }
        failing.start()
        while failingSource.requests.isEmpty { await Task.yield() }
        failingSource.requests[0].continuation.resume(throwing: NSError(domain: "capture-failure", code: 2))
        for _ in 0..<100 where failing.busy { await Task.yield() }
        expect(!failing.busy && failing.overlays.isEmpty && errors.count == 1, "后台截图失败会清理选区并允许重试")
        failing.cancel()
    }
}
