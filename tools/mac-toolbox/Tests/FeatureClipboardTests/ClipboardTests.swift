import AppKit
import Testing
import ToolboxCore
@testable import FeatureClipboard

/// 每个测试用独立的临时目录和私有剪贴板，不碰真实的历史和系统剪贴板
struct ClipStoreTests {
    func makeStore() -> ClipStore {
        ClipStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("xtools-tests-\(UUID().uuidString)"))
    }

    func text(_ value: String, date: Date = Date(), pinned: Bool = false) -> ClipItem {
        ClipItem(kind: .text, text: value, date: date, pinned: pinned,
                 fingerprint: ClipItem.fingerprint(kind: .text, data: Data(value.utf8)))
    }

    @Test func 新记录在最前面且相同内容去重() {
        let store = makeStore()
        store.add(text("a"), limit: 10, keepDays: nil)
        store.add(text("b"), limit: 10, keepDays: nil)
        store.add(text("a"), limit: 10, keepDays: nil)
        #expect(store.items.map(\.text) == ["a", "b"])
    }

    @Test func 去重时保留收藏状态() {
        let store = makeStore()
        store.add(text("a"), limit: 10, keepDays: nil)
        store.togglePin(id: store.items[0].id)
        store.add(text("a"), limit: 10, keepDays: nil)
        #expect(store.items[0].pinned)
    }

    @Test func 超出数量和天数时清理但保留收藏() {
        let store = makeStore()
        store.add(text("旧收藏", date: Date().addingTimeInterval(-40 * 86_400), pinned: true), limit: 2, keepDays: nil)
        store.add(text("过期", date: Date().addingTimeInterval(-40 * 86_400)), limit: 2, keepDays: nil)
        store.add(text("1"), limit: 2, keepDays: 30)
        #expect(Set(store.items.map(\.text)) == ["1", "旧收藏"])
        store.add(text("2"), limit: 2, keepDays: 30)
        store.add(text("3"), limit: 2, keepDays: 30)
        #expect(store.items.map(\.text) == ["3", "2", "旧收藏"])
    }

    @Test func 移到最前和删除和清空() {
        let store = makeStore()
        for value in ["a", "b", "c"] { store.add(text(value), limit: 10, keepDays: nil) }
        store.moveToTop(id: store.items[2].id)  // a
        #expect(store.items.map(\.text) == ["a", "c", "b"])
        store.delete(id: store.items[1].id)
        #expect(store.items.map(\.text) == ["a", "b"])
        store.togglePin(id: store.items[1].id)
        store.clearUnpinned()
        #expect(store.items.map(\.text) == ["b"])
    }

    @Test func 按分类和搜索词筛选() {
        let store = makeStore()
        store.add(text("Hello World"), limit: 10, keepDays: nil)
        store.add(text("你好"), limit: 10, keepDays: nil)
        #expect(store.filtered(.all, query: "hello").map(\.text) == ["Hello World"])
        #expect(store.filtered(.image, query: "").isEmpty)
        #expect(store.filtered(.text, query: "").count == 2)
    }

    @Test func 重新打开能读回历史() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("xtools-tests-\(UUID().uuidString)")
        ClipStore(directory: directory).add(text("持久化"), limit: 10, keepDays: nil)
        #expect(ClipStore(directory: directory).items.map(\.text) == ["持久化"])
    }
}

@MainActor
struct ClipCaptureTests {
    func makeBoard() -> NSPasteboard {
        let board = NSPasteboard(name: NSPasteboard.Name("xtools.tests.\(UUID().uuidString)"))
        board.clearContents()
        return board
    }

    func makeStore() -> ClipStore {
        ClipStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("xtools-tests-\(UUID().uuidString)"))
    }

    @Test func 读取文字并保存富文本() throws {
        let board = makeBoard(), store = makeStore()
        let rich = NSAttributedString(string: "粗体", attributes: [.font: NSFont.boldSystemFont(ofSize: 14)])
        let item = NSPasteboardItem()
        item.setString("粗体", forType: .string)
        item.setData(try rich.data(from: NSRange(location: 0, length: rich.length),
                                   documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]), forType: .rtf)
        board.writeObjects([item])
        let clip = try #require(ClipCapture.read(board, store: store, options: .init(), source: nil))
        #expect(clip.kind == .text && clip.text == "粗体")
        #expect(clip.rtfFile != nil)
        // 写回：纯文本时不带 RTF
        let plain = ClipCapture.pasteboardItems(for: clip, store: store, plainText: true)
        #expect(plain.first?.data(forType: .rtf) == nil)
        let full = ClipCapture.pasteboardItems(for: clip, store: store, plainText: false)
        #expect(full.first?.data(forType: .rtf) != nil)
        board.releaseGlobally()
    }

    @Test func 密码管理器的隐藏内容不记录() {
        let board = makeBoard()
        let item = NSPasteboardItem()
        item.setString("p@ssw0rd", forType: .string)
        item.setString("", forType: .init("org.nspasteboard.ConcealedType"))
        board.writeObjects([item])
        #expect(ClipCapture.read(board, store: makeStore(), options: .init(), source: nil) == nil)
        board.releaseGlobally()
    }

    @Test func 读取文件() throws {
        let board = makeBoard()
        board.writeObjects([URL(fileURLWithPath: "/tmp/a.txt") as NSURL, URL(fileURLWithPath: "/tmp/b.png") as NSURL])
        let clip = try #require(ClipCapture.read(board, store: makeStore(), options: .init(), source: nil))
        #expect(clip.kind == .files)
        #expect(clip.filePaths == ["/tmp/a.txt", "/tmp/b.png"])
        #expect(ClipCapture.read(board, store: makeStore(), options: .init(recordFiles: false), source: nil) == nil)
        board.releaseGlobally()
    }

    @Test func 读取图片并记下xTools来源() throws {
        let board = makeBoard(), store = makeStore()
        let image = NSImage(size: CGSize(width: 8, height: 4), flipped: false) { rect in
            NSColor.red.setFill(); rect.fill(); return true
        }
        let item = NSPasteboardItem()
        item.setData(try #require(image.tiffRepresentation), forType: .tiff)
        item.setString("screenshot", forType: PasteboardService.sourceType)
        board.writeObjects([item])
        let clip = try #require(ClipCapture.read(board, store: store, options: .init(), source: nil))
        #expect(clip.kind == .image)
        #expect(clip.origin == "screenshot")
        #expect(clip.imageWidth ?? 0 > 0)
        #expect(FileManager.default.fileExists(atPath: try #require(store.imageURL(for: clip)).path))
        board.releaseGlobally()
    }

    @Test func 空白文字不记录() {
        let board = makeBoard()
        board.setString("   \n", forType: .string)
        #expect(ClipCapture.read(board, store: makeStore(), options: .init(), source: nil) == nil)
        board.releaseGlobally()
    }
}

struct ClipCardStyleTests {
    func text(_ value: String) -> ClipItem {
        ClipItem(kind: .text, text: value, fingerprint: value)
    }

    @Test func 颜色值卡片铺成该颜色() {
        let purple = ClipCardStyle.color(red: 95.0 / 255, green: 46.0 / 255, blue: 234.0 / 255)
        #expect(ClipCardStyle.detect(text("#5F2EEA")) == purple)
        #expect(ClipCardStyle.detect(text(" ffffff ")) == .color(red: 1, green: 1, blue: 1))
        #expect(ClipCardStyle.detect(text("#5F2EE")) == .plain)
    }

    @Test func 代码用黑底() {
        #expect(ClipCardStyle.detect(text("def hello_world():\n    print(1)")) == .code)
        #expect(ClipCardStyle.detect(text("SELECT * FROM t WHERE id = 1")) == .code)
        #expect(ClipCardStyle.detect(text("你好，这是一段普通文字")) == .plain)
    }

    @Test func 图片和文件() {
        #expect(ClipCardStyle.detect(ClipItem(kind: .image, fingerprint: "i")) == .image)
        #expect(ClipCardStyle.detect(ClipItem(kind: .files, filePaths: ["/a"], fingerprint: "f")) == .plain)
    }
}

/// 面板跟着鼠标出现的位置
@MainActor
struct ClipboardPanelPlacementTests {
    let main = CGRect(x: 0, y: 0, width: 1440, height: 875)
    let external = CGRect(x: 1440, y: 0, width: 2560, height: 1415)

    @Test func 鼠标在哪半边就贴哪边() {
        let left = ClipboardPanel.dockedFrame(in: main, mouseX: 300)
        let right = ClipboardPanel.dockedFrame(in: main, mouseX: 1200)
        #expect(left.minX == main.minX + ClipboardPanel.margin)
        #expect(right.maxX == main.maxX - ClipboardPanel.margin)
        #expect(right.height == main.height - ClipboardPanel.margin * 2)
    }

    @Test func 记住的位置挪到鼠标所在屏幕() {
        // 主屏右侧离右边 20、离上边 30 的面板，挪到外接屏后离边距离不变
        let saved = CGRect(x: 1440 - 20 - 400, y: 875 - 30 - 600, width: 400, height: 600)
        let moved = ClipboardPanel.place(saved, from: main, to: external)
        #expect(moved.maxX == external.maxX - 20)
        #expect(moved.maxY == external.maxY - 30)
        #expect(moved.size == saved.size)
        // 同一块屏幕不动
        #expect(ClipboardPanel.place(saved, from: main, to: main) == saved)
    }

    @Test func 放不下时缩小并放进屏幕() {
        let tall = CGRect(x: 1440 + 100, y: 0, width: 515, height: 1400)
        let moved = ClipboardPanel.place(tall, from: external, to: main)
        #expect(main.contains(moved))
        #expect(moved.height == main.height)
        // 原屏幕已拔掉：只收进目标屏幕
        #expect(main.contains(ClipboardPanel.place(CGRect(x: 5000, y: 0, width: 320, height: 600), from: nil, to: main)))
    }
}
