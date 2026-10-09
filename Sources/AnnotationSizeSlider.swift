import AppKit

final class AnnotationSizeSlider: NSView {
    private let caption = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    let slider = AnnotationTrackingSlider()
    var onChange: ((CGFloat) -> Void)?
    var onBegin: (() -> Void)? { didSet { slider.onBegin = onBegin } }
    var onEnd: (() -> Void)? { didSet { slider.onEnd = onEnd } }
    private var step = 0.1
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { CGSize(width: 100, height: 38) }
    init() {
        super.init(frame: .zero)
        caption.font = .systemFont(ofSize: 11); caption.textColor = .secondaryLabelColor
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor; valueLabel.alignment = .right
        slider.controlSize = .small; slider.isContinuous = true
        slider.target = self; slider.action = #selector(changed)
        [caption, valueLabel, slider].forEach(addSubview)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(title: String, value: CGFloat, range: ClosedRange<Double>, step: Double = 0.1) {
        caption.stringValue = title
        self.step = step
        slider.minValue = range.lowerBound; slider.maxValue = range.upperBound
        slider.doubleValue = Double(value)
        slider.setAccessibilityLabel(title)
        updateValue()
    }
    func configureStyle(for canvas: CanvasView) {
        let tool = canvas.settingsTool
        let mark = canvas.selectedMark
        if tool.isRedaction { configure(title: "强度", value: mark?.width ?? canvas.redactionStrength, range: 1...10) }
        else if tool == .text {
            let size = (mark?.textAttributes[.font] as? NSFont)?.pointSize ?? canvas.textSize
            configure(title: "字号", value: size, range: 8...96, step: 1)
        } else { configure(title: "粗细", value: mark?.width ?? canvas.markWidth, range: 0.5...20) }
    }
    func bindStyle(to canvas: CanvasView) {
        onBegin = { [weak canvas] in canvas?.beginStyleChange() }
        onEnd = { [weak canvas] in canvas?.endStyleChange() }
        onChange = { [weak canvas] value in
            guard let canvas else { return }
            if canvas.settingsTool.isRedaction { canvas.setRedactionStrength(value) }
            else if canvas.settingsTool == .text { canvas.setTextSize(value) }
            else { canvas.setMarkWidth(value) }
            canvas.restoreEditingFocus()
        }
    }
    func bindBrush(to canvas: CanvasView) {
        onChange = { [weak canvas] value in canvas?.redactionBrushSize = value; canvas?.restoreEditingFocus() }
    }
    private func updateValue() {
        let value = slider.doubleValue
        valueLabel.stringValue = value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
        slider.toolTip = "\(caption.stringValue)：\(valueLabel.stringValue)"
    }
    override func layout() {
        super.layout()
        caption.frame = CGRect(x: 0, y: 0, width: max(0, bounds.width - 34), height: 15)
        valueLabel.frame = CGRect(x: max(0, bounds.width - 34), y: 0, width: 34, height: 15)
        slider.frame = CGRect(x: 0, y: max(16, bounds.height - 20), width: bounds.width, height: 20)
    }
    @objc private func changed() {
        slider.doubleValue = (slider.doubleValue / step).rounded() * step
        updateValue(); onChange?(CGFloat(slider.doubleValue))
    }
}

final class AnnotationTrackingSlider: NSSlider {
    var onBegin: (() -> Void)?
    var onEnd: (() -> Void)?
    override func mouseDown(with event: NSEvent) {
        onBegin?()
        defer { onEnd?() }
        super.mouseDown(with: event)
    }
}
