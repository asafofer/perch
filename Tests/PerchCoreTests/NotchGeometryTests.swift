import Testing
import CoreGraphics
@testable import PerchCore

@Suite struct NotchGeometryTests {
    let notched = ScreenInfo(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), notchSize: CGSize(width: 185, height: 32))
    let plain = ScreenInfo(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), notchSize: nil)

    @Test func idleUsesHardwareNotchWhenPresent() {
        #expect(NotchGeometry.idleSize(for: notched) == CGSize(width: 185, height: 32))
    }
    @Test func idleIsInvisibleWithoutNotch() {
        #expect(NotchGeometry.idleSize(for: plain).width == NotchGeometry.tabWidth)
        #expect(NotchGeometry.idleSize(for: ScreenInfo(frame: plain.frame, notchSize: nil, menuBarHeight: 40)).height == 28)
    }
    @Test func panelIsTopCentred() {
        let f = NotchGeometry.panelFrame(for: notched)
        #expect(f.midX == notched.frame.midX)
        #expect(f.maxY == notched.frame.maxY)
    }
    @Test func panelIsWiderThanTheCard() {
        #expect(NotchGeometry.panelSize.width > NotchGeometry.cardWidth)
    }
    @Test func contentRectOnSecondDisplayUsesItsOwnOrigin() {
        let second = ScreenInfo(frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080), notchSize: nil)
        let r = NotchGeometry.contentRect(width: 360, height: 160, screen: second)
        #expect(r.midX == second.frame.midX)
        #expect(r.maxY == second.frame.maxY)
    }
}
