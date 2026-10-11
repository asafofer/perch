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
        #expect(f.maxY == notched.frame.maxY + NotchGeometry.overscan)
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

@Suite struct ScreenPickerTests {
    // The laptop, and an external display to its left whose top sits above the laptop's (as on a desk).
    let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let external = CGRect(x: -3440, y: 129, width: 3440, height: 1440)

    @Test func insideIsFound() {
        #expect(ScreenPicker.index(of: CGPoint(x: 700, y: 500), in: [laptop, external]) == 0)
        #expect(ScreenPicker.index(of: CGPoint(x: -1700, y: 800), in: [laptop, external]) == 1)
    }
    @Test func theTopRowOfTheExternalScreenIsTheExternalScreen() {
        // Hovering a notch puts the cursor at y == maxY, which NSRect.contains does not count as inside.
        #expect(external.contains(CGPoint(x: -1720, y: external.maxY)) == false)
        #expect(ScreenPicker.index(of: CGPoint(x: -1720, y: external.maxY), in: [laptop, external]) == 1)
    }
    @Test func theTopRowOfTheLaptopIsTheLaptop() {
        #expect(ScreenPicker.index(of: CGPoint(x: 756, y: laptop.maxY), in: [laptop, external]) == 0)
    }
    @Test func aSharedEdgeBelongsToTheScreenWhoseInteriorHasIt() {
        let upper = CGRect(x: 0, y: 982, width: 1512, height: 800)
        #expect(ScreenPicker.index(of: CGPoint(x: 10, y: 982), in: [laptop, upper]) == 1)
        #expect(ScreenPicker.index(of: CGPoint(x: 10, y: 982), in: [upper, laptop]) == 0)
    }
    @Test func offEveryScreenIsNil() {
        #expect(ScreenPicker.index(of: CGPoint(x: 5000, y: 5000), in: [laptop, external]) == nil)
    }
}
