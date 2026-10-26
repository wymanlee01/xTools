import CoreGraphics
import Testing
@testable import FeatureWindow

struct WindowGeometryTests {
    /// 1440×900 的屏幕去掉菜单栏和程序坞后的可用区域
    let screen = CGRect(x: 0, y: 70, width: 1440, height: 800)

    @Test func 半屏和四分之一() {
        #expect(WindowGeometry.frame(for: .leftHalf, in: screen) == CGRect(x: 0, y: 70, width: 720, height: 800))
        #expect(WindowGeometry.frame(for: .rightHalf, in: screen) == CGRect(x: 720, y: 70, width: 720, height: 800))
        #expect(WindowGeometry.frame(for: .topHalf, in: screen) == CGRect(x: 0, y: 470, width: 1440, height: 400))
        #expect(WindowGeometry.frame(for: .bottomRight, in: screen) == CGRect(x: 720, y: 70, width: 720, height: 400))
        #expect(WindowGeometry.frame(for: .maximize, in: screen) == screen)
    }

    @Test func 间距在边缘和窗口之间都一样() throws {
        let left = try #require(WindowGeometry.frame(for: .leftHalf, in: screen, gap: 10))
        let right = try #require(WindowGeometry.frame(for: .rightHalf, in: screen, gap: 10))
        #expect(left.minX == 10)
        #expect(right.minX - left.maxX == 10)
        #expect(screen.maxX - right.maxX == 10)
        #expect(left.minY == screen.minY + 10)
    }

    @Test func 固定区域以外的动作没有目标位置() {
        for action in [WindowAction.center, .restore, .nextDisplay, .previousDisplay] {
            #expect(WindowGeometry.frame(for: action, in: screen) == nil)
        }
    }

    @Test func 居中保持大小放不下就缩小() {
        let centered = WindowGeometry.centered(CGRect(x: 0, y: 0, width: 400, height: 300), in: screen)
        #expect(centered == CGRect(x: 520, y: 320, width: 400, height: 300))
        let big = WindowGeometry.centered(CGRect(x: 0, y: 0, width: 2000, height: 300), in: screen)
        #expect(big.width == screen.width && big.minX == screen.minX)
    }

    @Test func 换屏按比例保持布局() {
        let external = CGRect(x: 1440, y: 0, width: 2560, height: 1415)
        let leftHalf = CGRect(x: 0, y: 70, width: 720, height: 800)
        #expect(WindowGeometry.moved(leftHalf, from: screen, to: external) == CGRect(x: 1440, y: 0, width: 1280, height: 1415))
        // 结果一定整个落在新屏幕里
        let odd = CGRect(x: 1400, y: 60, width: 900, height: 900)
        #expect(external.contains(WindowGeometry.moved(odd, from: screen, to: external)))
    }

    @Test func 找所在屏幕和左右邻居() {
        let screens = [screen, CGRect(x: 1440, y: 0, width: 2560, height: 1415), CGRect(x: -1080, y: 0, width: 1080, height: 1800)]
        #expect(WindowGeometry.screenIndex(for: CGRect(x: 1300, y: 100, width: 600, height: 400), in: screens) == 1)
        #expect(WindowGeometry.screenIndex(for: CGRect(x: 9000, y: 0, width: 10, height: 10), in: screens) == nil)
        // 从左到右：竖屏(2) → 主屏(0) → 外接屏(1)，首尾循环
        #expect(WindowGeometry.neighborIndex(of: 0, in: screens, forward: true) == 1)
        #expect(WindowGeometry.neighborIndex(of: 1, in: screens, forward: true) == 2)
        #expect(WindowGeometry.neighborIndex(of: 0, in: screens, forward: false) == 2)
    }

    @Test func Cocoa坐标和辅助功能坐标互换() {
        let cocoa = CGRect(x: 100, y: 70, width: 720, height: 800)
        let ax = WindowGeometry.toAX(cocoa, primaryHeight: 900)
        #expect(ax == CGRect(x: 100, y: 30, width: 720, height: 800))
        #expect(WindowGeometry.fromAX(ax, primaryHeight: 900) == cocoa)
    }

    @Test func 每个动作都有不同的默认快捷键() {
        let hotkeys = WindowAction.allCases.map(\.defaultHotkey)
        #expect(Set(hotkeys).count == hotkeys.count)
    }

    @Test func 菜单名不重复且顺序同菜单() {
        let titles = WindowAction.allCases.map(\.menuTitle)
        #expect(Set(titles).count == titles.count)
        #expect(Array(titles[8...9]) == ["下一个显示器", "上一个显示器"])
    }
}
