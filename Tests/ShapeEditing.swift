import AppKit

extension Tests {
    @MainActor static func shapeEditing(base: CGImage) throws {
        for tool in [MarkTool.arrow, .line, .rectangle, .blur, .mosaic] {
            let size = CGSize(width: 300, height: 240)
            let canvas = CanvasView(base: base, size: size)
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless,
                                  backing: .buffered, defer: false)
            window.contentView = canvas
            canvas.tool = tool
            func event(_ type: NSEvent.EventType, _ p: CGPoint, shift: Bool = false) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: canvas.convert(CGPoint(x: p.x * canvas.scale, y: p.y * canvas.scale), to: nil),
                                  modifierFlags: shift ? [.shift] : [], timestamp: 0, windowNumber: window.windowNumber,
                                  context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            func drag(from start: CGPoint, to end: CGPoint, shift: Bool = false) {
                canvas.mouseDown(with: event(.leftMouseDown, start))
                canvas.mouseDragged(with: event(.leftMouseDragged, end, shift: shift))
                canvas.mouseUp(with: event(.leftMouseUp, end))
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
            }
            drag(from: CGPoint(x: 40, y: 40), to: CGPoint(x: 180, y: tool.isRegion ? 140 : 40))
            let original = canvas.marks[0]
            expect(original.editingHandles.count == (tool.isRegion ? 4 : 2), "\(tool.title)具有可拖动控制点")
            canvas.updateTrackingAreas()
            canvas.mouseMoved(with: event(.mouseMoved, CGPoint(x: 110, y: 40)))
            expect(NSCursor.current === NSCursor.openHand, "悬停\(tool.title)非端点区域显示展开手形")
            canvas.cursorUpdate(with: event(.mouseMoved, original.editingHandles[0]))
            let resizeCursor = NSCursor.current
            expect(resizeCursor !== NSCursor.openHand && resizeCursor !== NSCursor.crosshair, "悬停\(tool.title)端点显示调整光标")
            canvas.mouseDown(with: event(.leftMouseDown, original.editingHandles[0]))
            canvas.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 30, y: 30)))
            expect(NSCursor.current === resizeCursor, "\(tool.title)端点拖动中保持调整光标")
            canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: 30, y: 30)))
            canvas.undo()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
            canvas.mouseDown(with: event(.leftMouseDown, CGPoint(x: 110, y: 40)))
            expect(NSCursor.current === NSCursor.closedHand, "按下\(tool.title)非端点区域显示握紧手形")
            canvas.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 130, y: 65)))
            expect(NSCursor.current === NSCursor.closedHand, "整体移动\(tool.title)期间保持握紧手形")
            canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: 130, y: 65)))
            expect(NSCursor.current === NSCursor.openHand, "松开\(tool.title)后恢复展开手形")
            canvas.undo()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
            canvas.mouseMoved(with: event(.mouseMoved, CGPoint(x: 20, y: 200)))
            expect(NSCursor.current === NSCursor.crosshair, "移到空白处恢复绘制光标")
            for (index, handle) in original.editingHandles.enumerated() {
                let end = CGPoint(x: handle.x + 15, y: handle.y + 20)
                drag(from: handle, to: end)
                let resized = canvas.marks[0]
                let opposite = original.editingHandles[tool.isRegion ? (index + 2) % 4 : 1 - index]
                expect(canvas.marks.count == 1 && resized.editingHandles.contains(end), "\(tool.title)控制点 \(index + 1) 可以二次拖动")
                expect(resized.editingHandles.contains(opposite), "\(tool.title)调整控制点时固定另一端")
                canvas.undo()
                expect(canvas.marks[0].points == original.points, "\(tool.title)端点调整可以撤销")
                canvas.redo()
                expect(canvas.marks[0].points == resized.points, "\(tool.title)端点调整可以重做")
                canvas.undo()
            }
            let body = CGPoint(x: 110, y: 40)
            drag(from: body, to: CGPoint(x: 130, y: 65))
            expect(canvas.marks.count == 1 && canvas.marks[0].points == original.points.map { CGPoint(x: $0.x + 20, y: $0.y + 25) },
                   "\(tool.title)拖动非端点区域整体移动，无需切换选择工具")
            canvas.undo()
            expect(canvas.marks[0].points == original.points, "\(tool.title)整体移动可以撤销")
            canvas.tool = .select
            canvas.setFrameSize(CGSize(width: 150, height: 120))
            canvas.mouseMoved(with: event(.mouseMoved, original.editingHandles[0]))
            expect(NSCursor.current !== NSCursor.arrow && NSCursor.current !== NSCursor.openHand, "缩放后悬停\(tool.title)控制点仍显示调整光标")
            drag(from: original.editingHandles[0], to: CGPoint(x: 30, y: 25))
            expect(canvas.marks[0].editingHandles.contains(CGPoint(x: 30, y: 25)), "\(tool.title)在缩放画布和选择工具下仍能调整端点")
            canvas.undo()
            canvas.setFrameSize(size)
            if tool.isRegion {
                drag(from: original.editingHandles[0], to: CGPoint(x: 210, y: 170))
                canvas.mouseDown(with: event(.leftMouseDown, CGPoint(x: 210, y: 170)))
                canvas.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 230, y: 190)))
                canvas.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 160, y: 120)))
                canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: 160, y: 120)))
                expect(canvas.marks[0].bounds == CGRect(x: 160, y: 120, width: 20, height: 20),
                       "方框角点连续跨过对角时不会跳动或移动固定角")
                canvas.undo(); canvas.undo()
                drag(from: original.editingHandles[0], to: CGPoint(x: 30, y: 20), shift: true)
                expect(canvas.marks[0].bounds.width == canvas.marks[0].bounds.height, "Shift 调整方框保持正方形")
            } else {
                drag(from: original.editingHandles[1], to: CGPoint(x: 190, y: 50), shift: true)
                expect(abs(canvas.marks[0].points[1].y - original.points[0].y) < 0.001, "Shift 调整\(tool.title)保持方向约束")
            }
            canvas.tool = tool
            drag(from: CGPoint(x: 20, y: 200), to: CGPoint(x: 100, y: 210))
            expect(canvas.marks.count == 2, "空白位置仍可继续绘制\(tool.title)")
            window.close()
        }
    }
}
