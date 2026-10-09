import AppKit

extension Tests {
    @MainActor static func textEditing(canvas: CanvasView, window: NSWindow, view: NSView) throws {
        let originalCount = canvas.marks.count
        canvas.tool = .text
        canvas.markColor = .systemBlue
        func begin(x: CGFloat = 20, y: CGFloat = 20) -> AnnotationTextEditor {
            let event = NSEvent.mouseEvent(with: .leftMouseDown, location: canvas.convert(CGPoint(x: x, y: y), to: nil),
                                          modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                          context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            canvas.mouseDown(with: event)
            return canvas.subviews.compactMap { $0 as? AnnotationTextEditor }.first!
        }
        func returnKey(modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                             windowNumber: window.windowNumber, context: nil, characters: "\r",
                             charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
        }
        let editor = begin()
        let input = editor.textView
        expect(window.firstResponder === input, "多行编辑区获得原生文字焦点")
        NSCursor.iBeam.set()
        let hover = NSEvent.mouseEvent(with: .mouseMoved, location: input.convert(CGPoint(x: 5, y: 5), to: nil),
                                       modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                       context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
        canvas.mouseMoved(with: hover)
        expect(NSCursor.current === NSCursor.iBeam, "画布悬停反馈不覆盖文字输入区的文字光标")
        expect(editor.subviews.count == 1 && editor.subviews.first === input && !input.drawsBackground && editor.layer == nil, "文字直接透明叠加在截图上，没有输入框、提示或按钮")
        input.insertText("第一行", replacementRange: NSRange(location: NSNotFound, length: 0))
        input.keyDown(with: returnKey(modifiers: .shift))
        input.breakUndoCoalescing()
        input.insertText("第二行", replacementRange: NSRange(location: NSNotFound, length: 0))
        expect(input.string == "第一行\n第二行" && canvas.marks.count == originalCount, "Shift 回车插入换行并保持编辑状态")
        expect(input.undoManager !== canvas.undoManager, "文字输入使用独立撤销历史")
        input.undoManager?.undo()
        expect(input.string != "第一行\n第二行" && canvas.marks.count == originalCount, "输入期间撤销只影响文字")
        input.undoManager?.redo()
        expect(input.string == "第一行\n第二行", "输入期间可重做文字")
        if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".build/text-editor-preview.png"))
        }
        input.keyDown(with: returnKey())
        let mark = canvas.marks.last!
        expect(mark.text == "第一行\n第二行" && canvas.marks.count == originalCount + 1, "回车将多行文字作为一个标注提交")
        expect(window.firstResponder === canvas && editor.superview == nil, "完成后关闭输入框并恢复画布焦点")
        let single = Annotation(tool: .text, points: mark.points, color: mark.color, width: mark.width, text: "第一行")
        expect(mark.bounds.height > single.bounds.height * 1.8, "多行标注的选中范围包含第二行")
        expect(mark.contains(CGPoint(x: mark.bounds.midX, y: mark.bounds.maxY - 5)), "第二行文字可以选中")
        let image = Renderer.image(base: canvas.base, logicalSize: canvas.logicalSize, marks: [mark])!
        let bitmap = NSBitmapImageRep(cgImage: image)
        let ratio = CGFloat(image.height) / canvas.logicalSize.height
        let lowerLine = CGRect(x: mark.bounds.minX, y: mark.bounds.minY + single.bounds.height,
                               width: mark.bounds.width, height: single.bounds.height)
        var bluePixels = 0
        for y in Int(lowerLine.minY * ratio)..<Int(lowerLine.maxY * ratio) {
            for x in Int(lowerLine.minX * ratio)..<Int(lowerLine.maxX * ratio) {
                let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                if color.blueComponent - color.redComponent > 0.3 { bluePixels += 1 }
            }
        }
        expect(bluePixels > 20, "导出图片保留第二行文字及标注颜色")
        canvas.undo()
        expect(canvas.marks.count == originalCount, "撤销一次移除完整多行标注")
        canvas.redo()
        expect(canvas.marks.last?.text == mark.text, "重做恢复完整多行标注")
        let edgeEditor = begin(x: canvas.logicalSize.width - 1, y: canvas.logicalSize.height - 1)
        expect(canvas.bounds.contains(edgeEditor.frame) && edgeEditor.frame.origin == CGPoint(x: canvas.bounds.maxX - 1, y: canvas.bounds.maxY - 1), "边缘输入保持点击位置，不移动文字")
        edgeEditor.textView.insertText("  缩进\n\n下一段  ", replacementRange: NSRange(location: NSNotFound, length: 0))
        edgeEditor.textView.keyDown(with: returnKey())
        expect(canvas.marks.last?.text == "  缩进\n\n下一段  ", "回车确认保留缩进、空行与末尾空格")
        let count = canvas.marks.count
        let emptyEditor = begin()
        emptyEditor.textView.insertText(" \n ", replacementRange: NSRange(location: NSNotFound, length: 0))
        canvas.commitText()
        expect(canvas.marks.count == count, "空白多行输入不产生标注")
        let growthBounds = CGRect(x: 0, y: 0, width: 500, height: 640)
        let growthEditor = AnnotationTextEditor(font: .systemFont(ofSize: 18, weight: .semibold))
        let growthHost = NSView(frame: growthBounds)
        growthHost.addSubview(growthEditor)
        growthEditor.place(at: CGPoint(x: 20, y: 20), within: growthBounds)
        expect(growthEditor.textView.enclosingScrollView == nil, "文字输入区没有滚动容器或滚动条")
        let initialHeight = growthEditor.frame.height
        growthEditor.textView.insertText("第一行", replacementRange: NSRange(location: NSNotFound, length: 0))
        let singleHeight = growthEditor.frame.height
        growthEditor.textView.keyDown(with: returnKey(modifiers: .shift))
        expect(growthEditor.frame.height > singleHeight && growthEditor.bounds.height >= growthEditor.textView.layoutManager!.extraLineFragmentRect.maxY,
               "末尾换行立即撑高输入框并完整容纳下一行光标")
        let manyLines = (1...14).map { "第\($0)行" }.joined(separator: "\n")
        growthEditor.textView.insertText(manyLines, replacementRange: NSRange(location: 0, length: growthEditor.textView.string.utf16.count))
        expect(growthEditor.frame.height > 220 && growthEditor.bounds.height >= growthEditor.textView.layoutManager!.usedRect(for: growthEditor.textView.textContainer!).maxY,
               "多行内容撑高超过旧的 220 点限制，文字完整显示")
        expect(growthBounds.contains(growthEditor.frame), "文字增高后仍保持在截图内")
        growthEditor.textView.insertText("短文本", replacementRange: NSRange(location: 0, length: growthEditor.textView.string.utf16.count))
        expect(growthEditor.frame.height == initialHeight && growthEditor.textView.frame.height == growthEditor.bounds.height,
               "删除多余行后文字编辑区域同步缩回")
    }
}
