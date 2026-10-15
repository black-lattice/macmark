import AppKit

final class HistoryWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let history: ScreenshotHistory
    private let table = NSTableView()
    private let preview = NSImageView()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let recording = NSButton(checkboxWithTitle: "记录最近 20 张截图", target: nil, action: nil)
    private var actions: [NSButton] = []
    var onOpen: ((CGImage) -> Void)?
    private var selection: ScreenshotHistory.Entry? {
        history.entries.indices.contains(table.selectedRow) ? history.entries[table.selectedRow] : nil
    }
    init(history: ScreenshotHistory) {
        self.history = history
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 780, height: 500),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "轻截 · 最近截图"; window.minSize = CGSize(width: 680, height: 400)
        window.isReleasedWhenClosed = false
        window.contentView = HistoryBackgroundView()
        super.init(window: window)
        buildUI()
        history.onChange = { [weak self] in
            if self?.window?.isVisible == true { self?.reload() }
        }
        reload(); window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func present() {
        reload(); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded; return button
    }
    private func buildUI() {
        guard let content = window?.contentView else { return }
        recording.target = self; recording.action = #selector(toggleRecording)
        recording.toolTip = "关闭后停止记录，已有历史可通过清空按钮删除"
        let clear = button("清空历史…", action: #selector(clearHistory))
        let header = NSStackView(views: [recording, NSView(), clear]); header.spacing = 12
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("capture"))
        column.width = 238; table.addTableColumn(column)
        table.headerView = nil; table.rowHeight = 76; table.intercellSpacing = CGSize(width: 0, height: 4)
        table.dataSource = self; table.delegate = self
        table.target = self; table.doubleAction = #selector(openSelected)
        table.setAccessibilityLabel("最近截图，双击继续标注")
        let list = NSScrollView(); list.documentView = table; list.hasVerticalScroller = true
        list.borderType = .bezelBorder
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.setContentHuggingPriority(.defaultLow, for: .vertical)
        preview.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        preview.setAccessibilityLabel("所选截图预览")
        status.textColor = .secondaryLabelColor; status.font = .systemFont(ofSize: 12)
        let open = button("继续标注", action: #selector(openSelected))
        let save = button("保存 PNG…", action: #selector(saveSelected))
        let copy = button("复制图片", action: #selector(copySelected))
        copy.keyEquivalent = "c"; copy.keyEquivalentModifierMask = .command
        actions = [open, save, copy]
        let footer = NSStackView(views: [NSView(), open, save, copy]); footer.spacing = 8
        for view in [header, list, preview, status, footer] {
            view.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            header.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            header.heightAnchor.constraint(equalToConstant: 24),
            list.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            list.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 16),
            list.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            list.widthAnchor.constraint(equalToConstant: 244),
            preview.leadingAnchor.constraint(equalTo: list.trailingAnchor, constant: 16),
            preview.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            preview.topAnchor.constraint(equalTo: list.topAnchor),
            preview.heightAnchor.constraint(greaterThanOrEqualToConstant: 160),
            status.leadingAnchor.constraint(equalTo: preview.leadingAnchor),
            status.widthAnchor.constraint(equalTo: preview.widthAnchor),
            status.topAnchor.constraint(equalTo: preview.bottomAnchor, constant: 12),
            footer.leadingAnchor.constraint(equalTo: preview.leadingAnchor),
            footer.widthAnchor.constraint(equalTo: preview.widthAnchor),
            footer.heightAnchor.constraint(equalToConstant: 24),
            footer.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 12),
            footer.bottomAnchor.constraint(equalTo: list.bottomAnchor)
        ])
        header.setContentHuggingPriority(.required, for: .vertical)
        status.setContentHuggingPriority(.required, for: .vertical)
        footer.setContentHuggingPriority(.required, for: .vertical)
    }
    func reload() {
        let id = selection?.id
        recording.state = history.isEnabled ? .on : .off
        table.reloadData()
        if !history.entries.isEmpty {
            let index = history.entries.firstIndex { $0.id == id } ?? 0
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
        updatePreview()
    }
    func numberOfRows(in tableView: NSTableView) -> Int { history.entries.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = history.entries[row]
        let cell = NSTableCellView(frame: CGRect(x: 0, y: 0, width: 238, height: 76))
        let image = NSImageView(frame: CGRect(x: 8, y: 8, width: 68, height: 60))
        image.imageScaling = .scaleProportionallyUpOrDown
        image.image = history.thumbnail(for: entry, maxSize: 160)
        let label = NSTextField(labelWithString: DateFormatter.localizedString(from: entry.date, dateStyle: .short, timeStyle: .medium))
        label.frame = CGRect(x: 86, y: 39, width: 146, height: 20); label.font = .systemFont(ofSize: 11)
        let dimensions = NSTextField(labelWithString: "\(entry.width) × \(entry.height)")
        dimensions.frame = CGRect(x: 86, y: 17, width: 146, height: 18)
        dimensions.font = .systemFont(ofSize: 11); dimensions.textColor = .secondaryLabelColor
        [image, label, dimensions].forEach(cell.addSubview)
        cell.imageView = image; cell.textField = label
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) { updatePreview() }
    private func updatePreview() {
        preview.image = selection.flatMap { history.thumbnail(for: $0, maxSize: 1200) }
        actions.forEach { $0.isEnabled = selection != nil }
        if let entry = selection {
            status.stringValue = "\(entry.width) × \(entry.height) 像素 · \(history.entries.count)/20 张\n保存的是最终图片，继续标注会在图片上添加新标注。"
        } else {
            status.stringValue = history.loadError ?? (history.isEnabled
                ? "暂无截图。复制、保存或锚定截图后，会自动保留在这里。"
                : "已关闭记录。开启后，新的截图会保存在本机。")
        }
    }
    private func selectedImage() -> CGImage? {
        guard let entry = selection else { return nil }
        guard let image = history.image(for: entry) else {
            ImageExport.showError("无法读取这张历史截图，文件可能已被移除或损坏。", window: window); return nil
        }
        return image
    }
    @objc private func openSelected() { if let image = selectedImage() { onOpen?(image) } }
    @objc func copySelected() { if let image = selectedImage() { ImageExport.copy(image, window: window) } }
    @objc func saveSelected() { if let image = selectedImage() { ImageExport.save(image, window: window) } }
    @objc private func toggleRecording() { history.isEnabled = recording.state == .on }
    @objc private func clearHistory() {
        guard let window else { return }
        let alert = NSAlert(); alert.messageText = "清空所有截图历史？"
        alert.informativeText = "只删除本机历史记录，不影响你另行保存的图片。"
        alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "清空")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertSecondButtonReturn, let self else { return }
            do { try self.history.clear() }
            catch { ImageExport.showError("清空失败：\(error.localizedDescription)", window: window) }
        }
    }
}

private final class HistoryBackgroundView: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) { NSColor.windowBackgroundColor.setFill(); dirtyRect.fill() }
}
