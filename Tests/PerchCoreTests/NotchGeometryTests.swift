import Testing
import CoreGraphics
@testable import PerchCore

@Suite struct NotchGeometryTests {
    let notched = ScreenInfo(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), notchSize: CGSize(width: 185, height: 32))
    let plain = ScreenInfo(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), notchSize: nil)

    @Test func idleUsesHardwareNotchWhenPresent() {
        #expect(NotchGeometry.idleSize(for: notched) == CGSize(width: 185, height: 32))
    }
    @Test func idleFallsBackToPillWithoutNotch() {
        #expect(NotchGeometry.idleSize(for: plain) == NotchGeometry.fallbackPillSize)
    }
    @Test func panelIsTopCentred() {
        let f = NotchGeometry.panelFrame(for: notched)
        #expect(f.midX == notched.frame.midX)
        #expect(f.maxY == notched.frame.maxY)
    }
    @Test func panelHoldsLargestCardWithMargin() {
        let f = NotchGeometry.panelFrame(for: plain)
        #expect(f.width >= NotchGeometry.openSize.width + NotchGeometry.shadowMargin * 2)
        #expect(f.height >= NotchGeometry.openSize.height)
    }
    @Test func contentRectOnSecondDisplayUsesItsOwnOrigin() {
        let second = ScreenInfo(frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080), notchSize: nil)
        let r = NotchGeometry.contentRect(for: .open, screen: second)
        #expect(r.midX == second.frame.midX)
        #expect(r.maxY == second.frame.maxY)
    }
}
