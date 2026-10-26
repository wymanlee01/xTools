import AppKit
import Carbon.HIToolbox
import CoreMedia
import ToolboxCore

/// 录屏设置，键名都在 “record.” 下；默认值取自 iShot 的默认设置
struct RecordSettings {
    let store: SettingsStore

    /// 默认 F5 开始/停止、⇧F5 暂停/恢复（iShot 用 ⌥W、⌥P，这里避开）
    static let defaultToggleHotkey = Hotkey(keyCode: kVK_F5, modifiers: [])
    static let defaultPauseHotkey = Hotkey(keyCode: kVK_F5, modifiers: [.shift])
    static let formats = ["mp4", "mov"]
    static let frameRates = [15, 25, 30, 60]
    static let countdowns = [0, 3, 5]

    var toggleHotkey: Hotkey? { store.hotkey("hotkey.toggle", default: Self.defaultToggleHotkey) }
    var pauseHotkey: Hotkey? { store.hotkey("hotkey.pause", default: Self.defaultPauseHotkey) }

    // 保存
    var saveDirectory: String {
        store.string("saveDirectory", default: FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0].path)
    }
    var askPath: Bool { store.bool("askPath", default: false) }
    /// 保存方式：0 本地文件、1 剪切板、2 同时保存到剪切板和本地
    var saveMethod: Int { store.int("saveMethod", default: 0) }
    /// 完成时动作：0 无、1 自动播放、2 打开路径
    var finishAction: Int { store.int("finishAction", default: 0) }

    // 录制选项（iShot 默认 mp4、25 帧、显示光标和点击、倒计时 3 秒）
    var format: String { store.string("format", default: "mp4") }
    var frameRate: Int { store.int("frameRate", default: 25) }
    var countdown: Int { store.int("countdown", default: 3) }
    var showsCursor: Bool { store.bool("showsCursor", default: true) }
    var showsClicks: Bool { store.bool("showsClicks", default: true) }
    var systemAudio: Bool { store.bool("systemAudio", default: false) }
    var microphone: Bool { store.bool("microphone", default: false) }
}

/// 暂停时间轴：暂停期间的时间从录像里扣掉（同 iShot 的 timeOffset / adjustTime:by:）
struct PauseClock {
    private(set) var isPaused = false
    /// 累计扣掉的时长
    private(set) var offset = CMTime.zero
    private var lastTime: CMTime?
    private var resumePending = false

    mutating func pause() {
        isPaused = true
    }

    mutating func resume() {
        guard isPaused else { return }
        isPaused = false
        resumePending = true
    }

    /// 处理一帧的时间：暂停中返回 nil（丢弃）；恢复后第一帧把暂停的间隔加进偏移
    mutating func adjust(_ time: CMTime) -> CMTime? {
        guard !isPaused else { return nil }
        if resumePending, let lastTime {
            offset = offset + (time - lastTime)
            resumePending = false
        }
        lastTime = time
        return time - offset
    }
}
