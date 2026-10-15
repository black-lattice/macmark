import AppKit

extension PinnedScreenshotController {
    func resize(by factor: CGFloat) {
        guard let window else { return }
        setScale(window.frame.width / originalSize.width * factor)
    }
    func setScale(_ scale: CGFloat) {
        guard let window, scale.isFinite, originalSize.width > 0, originalSize.height > 0 else { return }
        let frame = window.frame
        let bounds = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? frame
        let maximum = min(4, min(bounds.width / originalSize.width, bounds.height / originalSize.height))
        let value = min(maximum, max(0.1, scale))
        let size = CGSize(width: originalSize.width * value, height: originalSize.height * value)
        let preferred = CGRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                               width: size.width, height: size.height)
        window.setFrame(PinnedScreenshotManager.placement(size: size, preferredFrame: preferred, within: bounds), display: true)
    }
    func appendImageActions(to menu: NSMenu) {
        @discardableResult func add(_ title: String, _ action: Selector, tag: Int = 0, to targetMenu: NSMenu) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self; item.tag = tag; targetMenu.addItem(item)
            return item
        }
        add("复制图片", #selector(copyScreenshot(_:)), to: menu)
        add("保存 PNG…", #selector(saveScreenshot(_:)), to: menu)
        let scale = NSMenu(title: "缩放")
        for percentage in [25, 50, 75, 100, 150, 200] {
            let item = add("\(percentage)%", #selector(changeScale(_:)), tag: percentage, to: scale)
            item.state = abs((window?.frame.width ?? 0) / originalSize.width * 100 - CGFloat(percentage)) < 1 ? .on : .off
        }
        let scaleItem = NSMenuItem(title: "缩放（也可双指捏合）", action: nil, keyEquivalent: "")
        scaleItem.submenu = scale; menu.addItem(scaleItem)
        let opacity = NSMenu(title: "不透明度")
        for percentage in [25, 50, 75, 100] {
            let item = add("\(percentage)%", #selector(changeOpacity(_:)), tag: percentage, to: opacity)
            item.state = Int((window?.alphaValue ?? 1) * 100) == percentage ? .on : .off
        }
        let opacityItem = NSMenuItem(title: "不透明度", action: nil, keyEquivalent: "")
        opacityItem.submenu = opacity; menu.addItem(opacityItem)
        menu.addItem(.separator())
    }
    @objc func changeScale(_ sender: NSMenuItem) { setScale(CGFloat(sender.tag) / 100) }
    @objc func changeOpacity(_ sender: NSMenuItem) { window?.alphaValue = max(0.25, min(1, CGFloat(sender.tag) / 100)) }
    @objc func copyScreenshot(_ sender: Any?) { ImageExport.copy(image, window: window) }
    @objc func saveScreenshot(_ sender: Any?) { ImageExport.save(image, window: window) }
}
