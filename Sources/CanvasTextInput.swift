import AppKit

final class CanvasTextInput {
    private var editor: AnnotationTextEditor?
    private var origin = CGPoint.zero
    private var color: NSColor = .systemRed
    private var width: CGFloat = 3
    private var fontSize: CGFloat = 18
    func begin(on canvas: CanvasView, at point: CGPoint) {
        origin = point; color = canvas.markColor; width = canvas.markWidth; fontSize = canvas.textSize
        let editor = AnnotationTextEditor(font: .systemFont(ofSize: fontSize, weight: .semibold))
        editor.textView.textColor = color
        editor.onCommit = { [weak canvas] in canvas?.commitText(); canvas?.restoreEditingFocus() }
        editor.onCancel = { [weak canvas] in
            if let onCancel = canvas?.onCancel { onCancel() }
            else { canvas?.commitText(); canvas?.restoreEditingFocus() }
        }
        canvas.addSubview(editor); self.editor = editor
        editor.place(at: CGPoint(x: point.x * canvas.scale, y: point.y * canvas.scale), within: canvas.bounds, scale: canvas.scale)
        canvas.window?.makeFirstResponder(editor.textView)
    }
    func updateFont(size: CGFloat, scale: CGFloat) {
        fontSize = size
        editor?.updateFont(.systemFont(ofSize: size, weight: .semibold))
    }
    func restoreFocus(on canvas: CanvasView) { canvas.window?.makeFirstResponder((editor?.textView as NSView?) ?? canvas) }
    func commit(on canvas: CanvasView) -> Annotation? {
        guard let editor else { return nil }
        let text = editor.textView.string
        canvas.window?.makeFirstResponder(canvas)
        editor.removeFromSuperview(); self.editor = nil
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return Annotation(tool: .text, points: [origin], color: color, width: width, text: text, fontSize: fontSize)
    }
}
