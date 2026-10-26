import CoreGraphics
import Testing
@testable import FeatureScreenshot

struct SelectionGeometryTests {
    @Test func 反向拖拽也能得到正矩形() {
        let rect = SelectionGeometry.rect(from: CGPoint(x: 100, y: 80), to: CGPoint(x: 40, y: 20))
        #expect(rect == CGRect(x: 40, y: 20, width: 60, height: 60))
    }

    @Test func 视图坐标转像素坐标会翻转Y轴并乘倍率() {
        // 屏幕高 100 点，2 倍屏；选区在左下角 (10,10) 大小 20×30
        let rect = SelectionGeometry.pixelRect(for: CGRect(x: 10, y: 10, width: 20, height: 30),
                                               viewHeight: 100, scale: 2,
                                               imageSize: CGSize(width: 400, height: 200))
        #expect(rect == CGRect(x: 20, y: 120, width: 40, height: 60))
    }

    @Test func 超出图片的部分会被裁掉() {
        let rect = SelectionGeometry.pixelRect(for: CGRect(x: -10, y: 0, width: 50, height: 100),
                                               viewHeight: 100, scale: 1,
                                               imageSize: CGSize(width: 200, height: 100))
        #expect(rect == CGRect(x: 0, y: 0, width: 40, height: 100))
    }

    @Test func 副屏上的窗口坐标转换() {
        // 主屏高 1000；副屏在主屏右侧，frame 原点 (1440, 0)
        let rect = SelectionGeometry.viewRect(forGlobal: CGRect(x: 1500, y: 100, width: 300, height: 200),
                                              primaryScreenHeight: 1000,
                                              screenFrame: CGRect(x: 1440, y: 0, width: 1920, height: 1000))
        #expect(rect == CGRect(x: 60, y: 700, width: 300, height: 200))
    }
}
