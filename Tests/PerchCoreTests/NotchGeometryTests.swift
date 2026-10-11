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
    @Test func pillHoverCoversThePillAndTheTopEdge() {
        let r = NotchGeometry.pillHoverRect(for: plain)
        #expect(r.midX == plain.frame.midX)
        // the pill itself
        #expect(r.contains(CGPoint(x: 960, y: 1080 - 2 - 9)))
        // the cursor parked on the top edge, aimed at it
        #expect(r.contains(CGPoint(x: 960, y: 1080)))
        // a little way off to the side is not the pill
        #expect(!r.contains(CGPoint(x: 960 + 40, y: 1080 - 10)))
        #expect(!r.contains(CGPoint(x: 960, y: 1080 - 40)))
    }
    @Test func pillHasEqualWholePointGapsInTheMenuBar() {
        // (reported menu bar height, pill top, pill height): the band is one point shorter than reported (the hairline)
        for (bar, top, h) in [(30.0, 5.0, 19.0), (24.0, 2.0, 19.0), (25.0, 3.0, 18.0), (38.0, 9.0, 19.0)] as [(CGFloat, CGFloat, CGFloat)] {
            let p = NotchGeometry.pill(for: ScreenInfo(frame: plain.frame, notchSize: nil, menuBarHeight: bar))
            #expect(p.top == top && p.size.height == h)
            #expect(p.top == bar - 1 - p.top - p.size.height)   // the same gap above and below
        }
    }
    @Test func panelIsTopCentred() {
        let f = NotchGeometry.panelFrame(for: notched)
        #expect(f.midX == notched.frame.midX)
        #expect(f.maxY == notched.frame.maxY + NotchGeometry.overscan)
    }
    @Test func panelHoldsTheTallestSettingsCard() {
        // eleven rows (an external display, no Accessibility) at 30 pt, plus the header and footer: 408 pt
        #expect(NotchGeometry.panelSize.height >= 408)
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
    @Test func sweepingTheExternalTopEdgeNeverLandsOnTheLaptop() {
        // Along the whole top row, both corners included, the panel stays on the external display.
        for x in stride(from: external.minX, through: external.maxX, by: 0.25) {
            #expect(ScreenPicker.index(of: CGPoint(x: x, y: external.maxY), in: [laptop, external]) == 1)
            #expect(ScreenPicker.index(of: CGPoint(x: x, y: external.maxY), in: [external, laptop]) == 0)
        }
    }
    @Test func theSideTheyShareSwitchesOnceWhicheverWayTheyAreListed() {
        // Where the cursor crosses from one to the other, x == 0 is the laptop and anything left of it the external.
        for order in [[laptop, external], [external, laptop]] {
            let l = order.firstIndex(of: laptop), e = order.firstIndex(of: external)
            for y in stride(from: external.minY, through: laptop.maxY, by: 7) {
                #expect(ScreenPicker.index(of: CGPoint(x: 0, y: y), in: order) == l)
                #expect(ScreenPicker.index(of: CGPoint(x: -0.015625, y: y), in: order) == e)
            }
        }
    }
    @Test func offEveryScreenIsNil() {
        #expect(ScreenPicker.index(of: CGPoint(x: 5000, y: 5000), in: [laptop, external]) == nil)
    }
}
