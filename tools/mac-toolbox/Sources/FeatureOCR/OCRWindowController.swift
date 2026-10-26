import AppKit
import ToolboxCore

/// OCR 结果窗口，布局按 iShot 的界面：750×550、可调大小
/// 上方“识别结果”文本框；左下五个开关；右下“拷贝 / 拷贝后退出 / 翻译”
@MainActor
final class OCRWindowController: NSWindowController {
    private let settings: OCRSettings
    private let pasteboard: PasteboardService
    /// 识别出的原文（连续识别时累加），显示时再按开关处理
    private var rawText = ""

    private let textView = NSTextView()
    private let spinner = NSProgressIndicator()
    private var joinBox: NSButton!
    private var englishBox: NSButton!
    private var targets: [AnyObject] = []

    init(settings: OCRSettings, pasteboard: PasteboardService) {
        self.settings = settings
        self.pasteboard = pasteboard
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 750, height: 550),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "OCR 窗口"
        window.minSize = CGSize(width: 750, height: 550)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        buildLayout()
        window.level = settings.keepOnTop ? .floating : .normal
    }

    required init?(coder: NSCoder) { fatalError() }

    /// 开始识别：显示转圈
    func showLoading() {
        spinner.startAnimation(nil)
        present()
    }

    /// 显示识别结果；“连续识别模式”下追加到原有内容后面
    func show(_ text: String) {
        spinner.stopAnimation(nil)
        rawText = settings.continuous && !rawText.isEmpty ? rawText + "\n" + text : text
        refreshText()
        present()
    }

    private func present() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// 按“取消换行”“强制英文符号”处理后显示
    private func refreshText() {
        var text = rawText
        if joinBox.state == .on { text = TextRecognizer.joinLines(text) }
        if englishBox.state == .on { text = TextRecognizer.englishSymbols(text) }
        textView.string = text
    }

    private func copyText() {
        pasteboard.write(string: textView.string, source: "ocr")
    }

    // MARK: - 布局（坐标取自原版界面，原点在左下）

    private func buildLayout() {
        guard let root = window?.contentView else { return }
        let title = NSTextField(labelWithString: "识别结果:")
        title.font = .systemFont(ofSize: 15)
        title.frame = CGRect(x: 30, y: 485, width: 351, height: 22)
        title.autoresizingMask = [.minYMargin]
        root.addSubview(title)

        let scroll = NSScrollView(frame: CGRect(x: 30, y: 125, width: 690, height: 355))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.autoresizingMask = [.width, .height]
        textView.frame = CGRect(origin: .zero, size: scroll.contentSize)
        textView.autoresizingMask = [.width]
        textView.font = .systemFont(ofSize: 14)
        textView.isRichText = false
        textView.textContainerInset = CGSize(width: 6, height: 6)
        scroll.documentView = textView
        root.addSubview(scroll)

        spinner.style = .spinning
        spinner.isDisplayedWhenStopped = false
        spinner.frame = CGRect(x: 359, y: 285, width: 32, height: 32)
        spinner.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        root.addSubview(spinner)

        // 左下开关
        func checkbox(_ title: String, _ frame: CGRect, _ isOn: Bool, _ action: @escaping (Bool) -> Void) -> NSButton {
            let box = NSButton(checkboxWithTitle: title, target: nil, action: nil)
            box.frame = frame
            box.state = isOn ? .on : .off
            bind(box) { action(($0 as? NSButton)?.state == .on) }
            root.addSubview(box)
            return box
        }
        _ = checkbox("连续识别模式", CGRect(x: 34, y: 89, width: 140, height: 18), settings.continuous) { [weak self] in
            self?.settings.store.set($0, for: "window.continuous")
        }
        _ = checkbox("固定区域模式", CGRect(x: 34, y: 58, width: 140, height: 18), settings.fixedRegion) { [weak self] in
            self?.settings.store.set($0, for: "window.fixedRegion")
        }
        joinBox = checkbox("取消换行", CGRect(x: 34, y: 27, width: 140, height: 18), settings.joinLines) { [weak self] in
            self?.settings.store.set($0, for: "joinLines")
            self?.refreshText()
        }
        _ = checkbox("窗口置顶", CGRect(x: 193, y: 89, width: 127, height: 18), settings.keepOnTop) { [weak self] in
            self?.settings.store.set($0, for: "window.keepOnTop")
            self?.window?.level = $0 ? .floating : .normal
        }
        englishBox = checkbox("强制英文符号", CGRect(x: 194, y: 58, width: 124, height: 18), settings.englishSymbols) { [weak self] in
            self?.settings.store.set($0, for: "window.englishSymbols")
            self?.refreshText()
        }

        // 右下按钮
        func button(_ title: String, _ y: CGFloat, enabled: Bool = true, _ action: @escaping () -> Void) {
            let button = NSButton(title: title, target: nil, action: nil)
            button.bezelStyle = .rounded
            button.controlSize = .large
            button.frame = CGRect(x: 586, y: y, width: 134, height: 32)
            button.autoresizingMask = [.minXMargin]
            button.isEnabled = enabled
            bind(button) { _ in action() }
            root.addSubview(button)
        }
        button("拷贝", 78) { [weak self] in self?.copyText() }
        button("拷贝后退出", 44) { [weak self] in
            self?.copyText()
            self?.close()
        }
        button("翻译（开发中）", 10, enabled: false) {}
    }

    private func bind(_ control: NSControl, _ handler: @escaping (NSControl) -> Void) {
        let target = OCRControlTarget(handler)
        control.target = target
        control.action = #selector(OCRControlTarget.fire(_:))
        targets.append(target)
    }
}

/// 控件事件转闭包
private final class OCRControlTarget: NSObject {
    private let handler: (NSControl) -> Void
    init(_ handler: @escaping (NSControl) -> Void) { self.handler = handler }
    @objc func fire(_ sender: NSControl) { handler(sender) }
}
