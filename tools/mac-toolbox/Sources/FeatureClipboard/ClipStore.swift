import Foundation

/// 粘贴板历史的存储：items.json 记列表，图片和富文本单独存文件
/// 目录默认 ~/Library/Application Support/xTools/clipboard/
public final class ClipStore {
    public private(set) var items: [ClipItem] = []
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: rtfDirectory, withIntermediateDirectories: true)
        load()
    }

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("xTools/clipboard", isDirectory: true)
    }

    var imagesDirectory: URL { directory.appendingPathComponent("images", isDirectory: true) }
    var rtfDirectory: URL { directory.appendingPathComponent("rtf", isDirectory: true) }
    private var indexURL: URL { directory.appendingPathComponent("items.json") }

    public func imageURL(for item: ClipItem) -> URL? {
        item.imageFile.map { imagesDirectory.appendingPathComponent($0) }
    }

    public func rtfURL(for item: ClipItem) -> URL? {
        item.rtfFile.map { rtfDirectory.appendingPathComponent($0) }
    }

    // MARK: - 增删改

    /// 新增一条；内容相同的已有记录移到最前面（保留收藏状态），再按数量和天数清理
    public func add(_ item: ClipItem, limit: Int, keepDays: Int?) {
        var item = item
        if let index = items.firstIndex(where: { $0.fingerprint == item.fingerprint }) {
            let old = items.remove(at: index)
            item.pinned = old.pinned
            // 新记录的附件和旧记录相同，删掉新写的重复文件，沿用旧的
            if item.imageFile != old.imageFile { removeFiles(of: item) }
            item.imageFile = old.imageFile
            item.rtfFile = old.rtfFile
        }
        items.insert(item, at: 0)
        trim(limit: limit, keepDays: keepDays)
        save()
    }

    /// 移到最前面（从历史里粘贴后）
    public func moveToTop(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items.remove(at: index)
        item.date = Date()
        items.insert(item, at: 0)
        save()
    }

    public func togglePin(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].pinned.toggle()
        save()
    }

    public func delete(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        removeFiles(of: items.remove(at: index))
        save()
    }

    /// 清空历史（收藏的保留）
    public func clearUnpinned() {
        for item in items where !item.pinned { removeFiles(of: item) }
        items.removeAll { !$0.pinned }
        save()
    }

    /// 按数量、天数清理；收藏的不清理
    public func trim(limit: Int, keepDays: Int?) {
        var kept: [ClipItem] = []
        var unpinnedCount = 0
        let cutoff = keepDays.map { Date().addingTimeInterval(-Double($0) * 86_400) }
        for item in items {
            let tooOld = cutoff.map { item.date < $0 } ?? false
            if item.pinned || (!tooOld && unpinnedCount < limit) {
                kept.append(item)
                if !item.pinned { unpinnedCount += 1 }
            } else {
                removeFiles(of: item)
            }
        }
        items = kept
    }

    /// 按分类和搜索词筛选
    public func filtered(_ filter: ClipFilter, query: String) -> [ClipItem] {
        items.filter { filter.includes($0) && $0.matches(query) }
    }

    // MARK: - 读写磁盘

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        items = (try? decoder.decode([ClipItem].self, from: data)) ?? []
    }

    public func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private func removeFiles(of item: ClipItem) {
        // 其他记录还在用的附件不删
        if let file = item.imageFile, !items.contains(where: { $0.imageFile == file && $0.id != item.id }) {
            try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(file))
        }
        if let file = item.rtfFile, !items.contains(where: { $0.rtfFile == file && $0.id != item.id }) {
            try? FileManager.default.removeItem(at: rtfDirectory.appendingPathComponent(file))
        }
    }
}
