import AppKit
import UniformTypeIdentifiers
import ToolboxCore

/// 一张贴图：窗口 + 视图 + 状态（缩放比例、透明度、阴影），处理右键菜单和快捷键
@MainActor
final class PinController: NSObject {
    private(set) var image: CGImage
    /// 图片像素 / 点
    private let pixelScale: CGFloat
    /// 当前缩放比例（%），100 表示原始大小
    private var scale = 100
    private var opacity: CGFloat = 1
    /// 是否画光晕（右键“取消阴影 / 阴影”切换）
    private var glowEnabled = true
    /// 实际显示的图：圆角 + 四周留边的光晕
    private var decoratedImage: CGImage
    let window: PinWindow
    private let view: PinView
    private weak var manager: PinManager?

    var showsControls: Bool { manager?.settings.showsControls ?? true }

    /// 显示图（含留边）的原始大小（点），窗口大小 = 它 × 缩放比例
    private var baseSize: CGSize {
        CGSize(width: CGFloat(decoratedImage.width) / pixelScale, height: CGFloat(decoratedImage.height) / pixelScale)
    }

    init(image: CGImage, frame: CGRect?, pixelScale: CGFloat, manager: PinManager) {
        self.image = image
        self.pixelScale = pixelScale
        self.manager = manager
        decoratedImage = PinImageOps.decorated(image, pixelScale: pixelScale, cornerRadius: manager.settings.cornerRadius,
                                               glow: PinRules.activeGlow) ?? image
        let size = CGSize(width: CGFloat(decoratedImage.width) / pixelScale,
                          height: CGFloat(decoratedImage.height) / pixelScale)

        // 截图贴回原位：窗口比选区四周大一圈留边；否则放在鼠标所在屏幕中央，太大先缩小到屏幕 90% 以内
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        if frame == nil { scale = PinRules.initialScale(imageSize: size, screenSize: visible.size) }
        let shown = CGSize(width: size.width * CGFloat(scale) / 100, height: size.height * CGFloat(scale) / 100)
        let windowFrame = frame.map(PinRules.windowFrame(forContent:))
            ?? CGRect(x: visible.midX - shown.width / 2, y: visible.midY - shown.height / 2,
                      width: shown.width, height: shown.height)

        window = PinWindow(frame: windowFrame)
        view = PinView(frame: CGRect(origin: .zero, size: windowFrame.size), image: decoratedImage)
        super.init()
        view.controller = self
        view.autoresizingMask = [.width, .height]
        window.contentView = view
        opacity = manager.settings.defaultOpacity
        view.setOpacity(opacity)

        // 选中（成为当前窗口）时蓝色光晕，失去焦点时变回灰黑阴影
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(keyStateChanged), name: name, object: window)
        }
    }

    @objc private func keyStateChanged() {
        refreshDecoration()
    }

    /// 按当前状态重画显示图：选中蓝色光晕、未选中 50% 黑色阴影、关闭阴影则不画
    private func refreshDecoration() {
        let glow = glowEnabled ? (window.isKeyWindow ? PinRules.activeGlow : PinRules.inactiveGlow) : nil
        guard let radius = manager?.settings.cornerRadius,
              let result = PinImageOps.decorated(image, pixelScale: pixelScale, cornerRadius: radius, glow: glow)
        else { return }
        decoratedImage = result
        view.setImage(result)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
    }

    func close() {
        NotificationCenter.default.removeObserver(self)
        window.orderOut(nil)
        manager?.remove(self)
    }

    // MARK: - 缩放、透明度、变换

    /// 以 anchor（视图内的点）为中心缩放
    func zoom(byPercent delta: Int, anchor: CGPoint) {
        setScale(scale + delta, anchor: anchor)
    }

    func setScale(_ newValue: Int, anchor: CGPoint? = nil) {
        let target = PinRules.clampScale(newValue, baseSize: baseSize)
        guard target != scale else { return }
        let frame = window.frame
        let point = anchor ?? CGPoint(x: frame.width / 2, y: frame.height / 2)
        var newFrame = PinImageOps.zoomedFrame(frame, from: CGFloat(scale), to: CGFloat(target), anchor: point)
        newFrame = newFrame.integral
        scale = target
        window.setFrame(newFrame, display: true)
        view.showHint("\(scale)%")
    }

    func adjustOpacity(byPercent delta: Int) {
        setOpacity(opacity + CGFloat(delta) / 100)
        view.showHint("透明度 \(Int((opacity * 100).rounded()))%")
    }

    func setOpacity(_ value: CGFloat) {
        opacity = PinRules.clampOpacity(value)
        view.setOpacity(opacity)
    }

    /// 旋转、翻转：保持窗口中心不动
    func transform(_ kind: PinImageOps.Transform) {
        guard let result = PinImageOps.apply(kind, to: image) else { return }
        image = result
        refreshDecoration()
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        let size = CGSize(width: baseSize.width * CGFloat(scale) / 100, height: baseSize.height * CGFloat(scale) / 100)
        window.setFrame(CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                               width: size.width, height: size.height).integral, display: true)
    }

    func move(dx: CGFloat, dy: CGFloat) {
        window.setFrameOrigin(CGPoint(x: window.frame.minX + dx, y: window.frame.minY + dy))
    }

    func toggleShadow() {
        glowEnabled.toggle()
        refreshDecoration()
    }

    // MARK: - 拷贝、保存、打开方式

    func copyToPasteboard() {
        manager?.pasteboard.write(image: image, source: "pin")
    }

    func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH.mm.ss"
        panel.nameFieldStringValue = "xTools_\(formatter.string(from: Date())).png"
        panel.level = NSWindow.Level(rawValue: window.level.rawValue + 1)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? pngData()?.write(to: url)
    }

    /// 用其他应用打开：先存成临时 PNG，再交给选中的应用
    func open(with appURL: URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("xTools-pin-\(UUID().uuidString).png")
        guard (try? pngData()?.write(to: url)) != nil else { return }
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
    }

    private func pngData() -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    func showHelp() {
        let alert = NSAlert()
        alert.messageText = "贴图"
        alert.informativeText = "上下滚轮放大、缩小，按住 ⌥ 滚动调透明度，双击鼠标关闭贴图，点击右键查看更多操作。"
        alert.window.level = NSWindow.Level(rawValue: window.level.rawValue + 1)
        alert.runModal()
    }

    // MARK: - 右键菜单和快捷键（菜单项、快捷键与 iShot 一致）

    func contextMenu() -> NSMenu {
        let menu = NSMenu()
        func item(_ title: String, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = [.command],
                  enabled: Bool = true, action: @escaping () -> Void) {
            let menuItem = ClosureMenuItem(title: title, keyEquivalent: key, handler: action)
            menuItem.keyEquivalentModifierMask = modifiers
            menuItem.isEnabled = enabled
            menu.addItem(menuItem)
        }
        item("拷贝", "c") { [weak self] in self?.copyToPasteboard() }
        item("保存至贴图库（开发中）", "s", enabled: false) {}
        item("另存为...", "s", [.command, .shift]) { [weak self] in self?.saveAs() }
        menu.addItem(openWithItem())
        item("标注（开发中）", " ", [], enabled: false) {}
        item(glowEnabled ? "取消阴影" : "阴影", "h", []) { [weak self] in self?.toggleShadow() }
        menu.addItem(.separator())
        item("50%", "0", []) { [weak self] in self?.setScale(50) }
        item("100%", "1", []) { [weak self] in self?.setScale(100) }
        item("200%", "2", []) { [weak self] in self?.setScale(200) }
        menu.addItem(.separator())
        // 方向键在菜单里要用功能键字符表示
        func arrow(_ key: Int) -> String { String(UnicodeScalar(UInt16(key)).map(Character.init) ?? " ") }
        item("向左位移一个像素", arrow(NSLeftArrowFunctionKey), []) { [weak self] in self?.move(dx: -1, dy: 0) }
        item("向右位移一个像素", arrow(NSRightArrowFunctionKey), []) { [weak self] in self?.move(dx: 1, dy: 0) }
        item("向上位移一个像素", arrow(NSUpArrowFunctionKey), []) { [weak self] in self?.move(dx: 0, dy: 1) }
        item("向下位移一个像素", arrow(NSDownArrowFunctionKey), []) { [weak self] in self?.move(dx: 0, dy: -1) }
        menu.addItem(.separator())
        item("向左旋转") { [weak self] in self?.transform(.rotateLeft) }
        item("向右旋转") { [weak self] in self?.transform(.rotateRight) }
        item("水平翻转") { [weak self] in self?.transform(.flipHorizontal) }
        item("垂直翻转") { [weak self] in self?.transform(.flipVertical) }
        menu.addItem(.separator())
        item("关闭", "w") { [weak self] in self?.close() }
        item("全部关闭", "w", [.command, .shift]) { [weak self] in self?.manager?.closeAll() }
        item("隐藏/显示全部贴图") { [weak self] in self?.manager?.toggleAll() }
        return menu
    }

    /// “从文件打开...”：列出能打开 PNG 的应用
    private func openWithItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "从文件打开...", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for appURL in NSWorkspace.shared.urlsForApplications(toOpen: .png).prefix(12) {
            let name = FileManager.default.displayName(atPath: appURL.path)
            let item = ClosureMenuItem(title: name, keyEquivalent: "") { [weak self] in self?.open(with: appURL) }
            item.image = NSWorkspace.shared.icon(forFile: appURL.path)
            item.image?.size = CGSize(width: 16, height: 16)
            submenu.addItem(item)
        }
        parent.submenu = submenu
        return parent
    }

    /// 贴图获得焦点时的快捷键；返回 false 表示没处理
    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let char = event.charactersIgnoringModifiers?.lowercased() ?? ""
        switch (flags, char, event.keyCode) {
        case ([.command], "c", _): copyToPasteboard()
        case ([.command, .shift], "s", _): saveAs()
        case ([.command], "w", _): close()
        case ([.command, .shift], "w", _): manager?.closeAll()
        case ([], "0", _): setScale(50)
        case ([], "1", _): setScale(100)
        case ([], "2", _): setScale(200)
        case ([], "h", _): toggleShadow()
        case (_, _, 123): move(dx: -1, dy: 0)
        case (_, _, 124): move(dx: 1, dy: 0)
        case (_, _, 125): move(dx: 0, dy: -1)
        case (_, _, 126): move(dx: 0, dy: 1)
        default: return false
        }
        return true
    }
}

/// 用闭包处理点击的菜单项
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, keyEquivalent: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: keyEquivalent)
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func run() { handler() }
}
