import CoreMedia
import Foundation
import Testing
import ToolboxCore
@testable import FeatureRecord

struct PauseClockTests {
    func t(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 600) }

    @Test func 没暂停时时间不变() {
        var clock = PauseClock()
        #expect(clock.adjust(t(1)) == t(1))
        #expect(clock.adjust(t(2)) == t(2))
    }

    @Test func 暂停期间的帧丢弃且恢复后扣掉暂停时长() {
        var clock = PauseClock()
        _ = clock.adjust(t(1))
        _ = clock.adjust(t(2))
        clock.pause()
        #expect(clock.adjust(t(3)) == nil)  // 暂停中丢弃
        #expect(clock.adjust(t(4)) == nil)
        clock.resume()
        // 恢复后第一帧在 7 秒，和暂停前最后一帧（2 秒）之间隔了 5 秒，全部扣掉，接在 2 秒后面
        #expect(clock.adjust(t(7)) == t(2))
        #expect(clock.adjust(t(8)) == t(3))
    }

    @Test func 多次暂停累计偏移() {
        var clock = PauseClock()
        _ = clock.adjust(t(1))
        clock.pause(); clock.resume()
        #expect(clock.adjust(t(3)) == t(1))   // 扣 2 秒
        clock.pause(); clock.resume()
        #expect(clock.adjust(t(6)) == t(1))   // 再扣 3 秒
        #expect(clock.offset == t(5))
    }
}

struct RecordSettingsTests {
    @Test func 默认值和iShot一致() {
        let defaults = UserDefaults(suiteName: "xtools.tests.\(UUID().uuidString)")!
        let settings = RecordSettings(store: SettingsStore(defaults: defaults).scoped("record"))
        #expect(settings.format == "mp4")
        #expect(settings.frameRate == 25)
        #expect(settings.countdown == 3)
        #expect(settings.showsCursor && settings.showsClicks)
        #expect(settings.saveMethod == 0 && settings.finishAction == 0)
        #expect(settings.toggleHotkey?.displayName == "F5")
        #expect(settings.pauseHotkey?.displayName == "⇧F5")
    }
}
