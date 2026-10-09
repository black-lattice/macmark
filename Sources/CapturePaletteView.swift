import AppKit

final class CapturePaletteView: CaptureSurfaceView {
    private let canvas: CanvasView
    private let size = AnnotationSizeSlider()
    private let colorCaption = NSTextField(labelWithString: "颜色")
    private let mode = NSSegmentedControl(labels: ["框选", "涂抹"], trackingMode: .selectOne, target: nil, action: nil)
    private let brushSize = AnnotationSizeSlider()
    private var colorButtons: [NSButton] = []
    private let colors: [(String, NSColor)] = [("红色", .systemRed), ("橙色", .systemOrange), ("黄色", .systemYellow),
                                              ("绿色", .systemGreen), ("青色", .systemTeal), ("蓝色", .systemBlue),
                                              ("紫色", .systemPurple), ("粉色", .systemPink), ("黑色", .black), ("白色", .white)]
    init(canvas: CanvasView) {
        self.canvas = canvas
        super.init(frame: .zero)
        size.frame = CGRect(x: 8, y: 7, width: 96, height: 54)
        size.bindStyle(to: canvas); addSubview(size)
        label(colorCaption, at: 112)
        for (index, entry) in colors.enumerated() {
            let button = CaptureIconButton.make(entry.0, icon: nil, target: self, action: #selector(colorClicked(_:)), toggle: true, swatch: true)
            button.tag = index
            button.frame = CGRect(x: 110 + CGFloat(index % 5) * 21, y: 25 + CGFloat(index / 5) * 22, width: 20, height: 20)
            button.image = NSImage(size: CGSize(width: 14, height: 14), flipped: false) { rect in
                let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
                entry.1.setFill(); circle.fill()
                NSColor.lightGray.setStroke(); circle.lineWidth = 0.5; circle.stroke()
                return true
            }
            addSubview(button); colorButtons.append(button)
        }
        mode.target = self; mode.action = #selector(modeChanged(_:))
        mode.controlSize = .small; mode.font = .systemFont(ofSize: 11)
        mode.frame = CGRect(x: 110, y: 7, width: 104, height: 24)
        mode.setAccessibilityLabel("遮挡方式")
        brushSize.frame = CGRect(x: 110, y: 32, width: 104, height: 36)
        brushSize.bindBrush(to: canvas)
        addSubview(mode); addSubview(brushSize)
        update(tool: canvas.tool)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func label(_ field: NSTextField, at x: CGFloat) {
        field.font = .systemFont(ofSize: 11)
        field.textColor = .darkGray
        field.frame = CGRect(x: x, y: 7, width: 90, height: 15)
        addSubview(field)
    }
    func update(tool: MarkTool) {
        size.configureStyle(for: canvas)
        colorCaption.isHidden = tool.isRedaction
        mode.isHidden = !tool.isRedaction
        mode.selectedSegment = canvas.redactionMode.rawValue
        brushSize.isHidden = !tool.isRedaction || canvas.redactionMode != .brush
        brushSize.configure(title: "笔刷", value: canvas.redactionBrushSize, range: 6...200, step: 1)
        for (index, button) in colorButtons.enumerated() {
            button.isHidden = tool.isRedaction
            button.state = colors[index].1 == canvas.markColor ? .on : .off
        }
    }
    @objc private func colorClicked(_ sender: NSButton) {
        canvas.commitText(); canvas.markColor = colors[sender.tag].1
        update(tool: canvas.tool); window?.makeFirstResponder(canvas)
    }
    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        canvas.redactionMode = RedactionMode(rawValue: sender.selectedSegment) ?? .region
        update(tool: canvas.tool); window?.makeFirstResponder(canvas)
    }
}
