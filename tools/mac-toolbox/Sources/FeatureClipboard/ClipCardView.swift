import AppKit

/// 卡片的显示样式：按内容决定（同 PasteNow 官网截图里的效果）
public enum ClipCardStyle: Equatable {
    /// 普通文字、文件
    case plain
    /// 颜色值（#RRGGBB）：卡片直接铺成这个颜色
    case color(red: Double, green: Double, blue: Double)
    /// 代码：黑底等宽字体
    case code
    /// 图片：显示缩略图
    case image

    public static func detect(_ item: ClipItem) -> ClipCardStyle {
        switch item.kind {
        case .image: return .image
        case .files: return .plain
        case .text: break
        }
        let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        // #RRGGBB 或 RRGGBB
        let hex = text.hasPrefix("#") ? String(text.dropFirst()) : text
        if hex.count == 6, let value = Int(hex, radix: 16) {
            return .color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                          blue: Double(value & 0xFF) / 255)
        }
        // 代码：常见的语法特征
        let markers = ["{", "}", "def ", "func ", "class ", "import ", "return ", "=>", "();", "SELECT ", "select ",
                       "const ", "let ", "var ", "public ", "#include", "</"]
        if markers.contains(where: text.contains) { return .code }
        return .plain
    }
}

/// 列表里的一张卡片：左边来源应用图标，中间内容，右上时间，右下 “⌘ 1”
/// 卡片之间留空，选中时强调色描边
final class ClipCardView: NSTableCellView {
    /// 所有卡片一样高（同 PasteNow）：卡片 80 + 间距 10
    static let rowHeight: CGFloat = 90
    static let spacing: CGFloat = 10
    /// 卡片左右边距一样宽；右边距正好放下浮动滚动条（宽 17），滚动条不压卡片（同 PasteNow）
    static let sideMargin: CGFloat = 17

    private let card = NSView()
    private let style: ClipCardStyle
    var isSelected = false { didSet { updateBorder() } }

    init(item: ClipItem, index: Int, store: ClipStore, width: CGFloat) {
        style = ClipCardStyle.detect(item)
        super.init(frame: CGRect(x: 0, y: 0, width: width, height: Self.rowHeight))

        // 卡片本体：上下各留 5 点形成间距，左右边距相同
        card.frame = CGRect(x: Self.sideMargin, y: Self.spacing / 2, width: width - Self.sideMargin * 2,
                            height: Self.rowHeight - Self.spacing)
        card.autoresizingMask = [.width, .height]
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.backgroundColor = backgroundColor.cgColor
        card.layer?.borderWidth = 0
        addSubview(card)
        let w = card.bounds.width, h = card.bounds.height

        // 来源应用图标，竖直居中
        let iconImage = Self.icon(for: item)
        iconImage.size = CGSize(width: 26, height: 26)
        let icon = NSImageView(image: iconImage)
        icon.frame = CGRect(x: 14, y: (h - 26) / 2, width: 26, height: 26)
        card.addSubview(icon)

        // 内容
        let contentX: CGFloat = 50
        let contentWidth = w - contentX - 50
        if style == .image, let url = store.imageURL(for: item), let image = NSImage(contentsOf: url) {
            // 缩略图在卡片里等比缩小、居中，高度固定，不撑高卡片
            let thumb = NSImageView(image: image)
            thumb.imageScaling = .scaleProportionallyDown
            thumb.frame = CGRect(x: contentX, y: 12, width: contentWidth, height: h - 24)
            thumb.autoresizingMask = [.width]
            card.addSubview(thumb)
        } else {
            let text = NSTextField(wrappingLabelWithString: Self.display(item))
            text.font = style == .code ? .monospacedSystemFont(ofSize: 12, weight: .regular) : .systemFont(ofSize: 13)
            text.textColor = foregroundColor
            text.maximumNumberOfLines = 3
            text.lineBreakMode = .byTruncatingTail
            text.cell?.truncatesLastVisibleLine = true
            // 按实际行数（最多 3 行）算高度，让一行、两行的文字也在卡片里上下居中
            text.preferredMaxLayoutWidth = contentWidth
            let textHeight = min(ceil(text.fittingSize.height), 52)
            text.frame = CGRect(x: contentX, y: (h - textHeight) / 2, width: contentWidth, height: textHeight)
            text.autoresizingMask = [.width, .minYMargin, .maxYMargin]
            card.addSubview(text)
        }

        // 右上时间，右下 “⌘ N” 和收藏星标
        let time = Self.label(Self.timeText(item.date), color: foregroundColor.withAlphaComponent(0.5))
        time.alignment = .right
        time.frame = CGRect(x: w - 90, y: h - 20, width: 80, height: 13)
        time.autoresizingMask = [.minXMargin]
        card.addSubview(time)
        let shortcut = (item.pinned ? "★ " : "") + (index < 9 ? "⌘ \(index + 1)" : "")
        let badge = Self.label(shortcut, color: item.pinned ? .systemYellow : foregroundColor.withAlphaComponent(0.6),
                               weight: .semibold)
        badge.alignment = .right
        badge.frame = CGRect(x: w - 90, y: 7, width: 80, height: 13)
        badge.autoresizingMask = [.minXMargin]
        card.addSubview(badge)
        toolTip = [item.sourceName, item.origin.map { ["screenshot": "来自截图", "pin": "来自贴图", "ocr": "来自 OCR"][$0] ?? $0 }]
            .compactMap { $0 }.joined(separator: " · ")
    }

    required init?(coder: NSCoder) { fatalError() }

    private func updateBorder() {
        card.layer?.borderWidth = isSelected ? 2 : 0
        card.layer?.borderColor = NSColor.controlAccentColor.cgColor
    }

    /// 卡片底色：颜色值铺成该颜色，代码黑底，其余半透明白（深色模式半透明浅灰）
    private var backgroundColor: NSColor {
        switch style {
        case .color(let r, let g, let b): return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        case .code: return NSColor(white: 0.08, alpha: 1)
        default:
            let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return dark ? NSColor(white: 1, alpha: 0.08) : NSColor(white: 1, alpha: 0.72)
        }
    }

    /// 文字颜色：深底用白字，颜色卡按亮度选黑白
    private var foregroundColor: NSColor {
        switch style {
        case .color(let r, let g, let b): return 0.299 * r + 0.587 * g + 0.114 * b > 0.6 ? .black : .white
        case .code: return NSColor(white: 0.92, alpha: 1)
        default: return .labelColor
        }
    }

    private static func display(_ item: ClipItem) -> String {
        item.kind == .text ? item.text.trimmingCharacters(in: .whitespacesAndNewlines) : item.summary
    }

    private static func label(_ text: String, color: NSColor, weight: NSFont.Weight = .regular) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 10, weight: weight)
        label.textColor = color
        return label
    }

    /// 今天显示 “14:43”，更早显示 “2024/5/10”（同 PasteNow）
    static func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "yyyy/M/d"
        return formatter.string(from: date)
    }

    private static func icon(for item: ClipItem) -> NSImage {
        if let id = item.sourceBundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        let symbol = ["text": "doc.text", "image": "photo", "files": "folder"][item.kind.rawValue] ?? "doc"
        return NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage()
    }
}

/// 行视图不画系统的选中底色，选中效果由卡片描边表示
final class ClipRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {}
    override func drawBackground(in dirtyRect: NSRect) {}
}

/// 顶部的胶囊标签（全部 / 文字 / 图片 / 文件 / 收藏），选中项浅强调色底 + 强调色字
final class PillTabs: NSView {
    var onSelect: ((Int) -> Void)?
    private var buttons: [NSButton] = []
    private(set) var selected = 0

    init(titles: [String]) {
        super.init(frame: .zero)
        var x: CGFloat = 0
        for (index, title) in titles.enumerated() {
            let button = NSButton(title: title, target: self, action: #selector(clicked(_:)))
            button.tag = index
            button.isBordered = false
            button.font = .systemFont(ofSize: 12, weight: .medium)
            button.wantsLayer = true
            button.layer?.cornerRadius = 11
            let width = (title as NSString).size(withAttributes: [.font: button.font!]).width + 22
            button.frame = CGRect(x: x, y: 0, width: width, height: 22)
            addSubview(button)
            buttons.append(button)
            x += width + 4
        }
        frame.size = CGSize(width: x, height: 22)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func clicked(_ sender: NSButton) {
        selected = sender.tag
        refresh()
        onSelect?(selected)
    }

    private func refresh() {
        for button in buttons {
            let on = button.tag == selected
            button.layer?.backgroundColor = on ? NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor : nil
            button.contentTintColor = on ? .controlAccentColor : .secondaryLabelColor
            button.attributedTitle = NSAttributedString(string: button.title, attributes: [
                .font: button.font ?? .systemFont(ofSize: 12),
                .foregroundColor: on ? NSColor.controlAccentColor : NSColor.secondaryLabelColor,
            ])
        }
    }
}
