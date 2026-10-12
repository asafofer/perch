import Foundation
import Testing
@testable import PerchCore

@Suite struct PanelStrutsTests {
    // Two 1920x1080 displays side by side; the right one is a 2560x1440 in the second case.
    let left = CGRect(x: 0, y: 0, width: 1920, height: 1080), right = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
    let root = CGSize(width: 3840, height: 1080)

    @Test func aTopPanelOnOneDisplayLeavesTheOtherWhole() {
        let panel: [UInt] = [0, 0, 24, 0, 0, 0, 0, 0, 0, 1919, 0, 0]
        #expect(PanelStruts.free(left, root: root, struts: [panel]) == CGRect(x: 0, y: 24, width: 1920, height: 1056))
        #expect(PanelStruts.free(right, root: root, struts: [panel]) == right)
    }

    @Test func aBottomPanelOnAShorterDisplayCountsFromTheScreensBottom() {
        // Left 1920x1080 at the top, right 2560x1440: the screen is 1440 high, so a panel at the bottom of the left
        // display reserves 360 + 30 from the screen's bottom edge.
        let tall = CGRect(x: 1920, y: 0, width: 2560, height: 1440), root = CGSize(width: 4480, height: 1440)
        let panel: [UInt] = [0, 0, 0, 390, 0, 0, 0, 0, 0, 0, 0, 1919]
        #expect(PanelStruts.free(left, root: root, struts: [panel]) == CGRect(x: 0, y: 0, width: 1920, height: 1050))
        #expect(PanelStruts.free(tall, root: root, struts: [panel]) == tall)
    }

    @Test func sidePanelsAndAnOldStyleStrutAcrossTheWholeEdge() {
        let dock: [UInt] = [48, 0, 0, 0, 0, 1079, 0, 0, 0, 0, 0, 0]
        let whole: [UInt] = [0, 0, 30, 0, 0, .max, 0, .max, 0, .max, 0, .max]
        #expect(PanelStruts.free(left, root: root, struts: [dock, whole]) == CGRect(x: 48, y: 30, width: 1872, height: 1050))
        #expect(PanelStruts.free(right, root: root, struts: [dock, whole]) == CGRect(x: 1920, y: 30, width: 1920, height: 1050))
        // A right panel on the right display.
        let rightDock: [UInt] = [0, 64, 0, 0, 0, 0, 0, 1079, 0, 0, 0, 0]
        #expect(PanelStruts.free(right, root: root, struts: [rightDock]) == CGRect(x: 1920, y: 0, width: 1856, height: 1080))
        #expect(PanelStruts.free(left, root: root, struts: [rightDock]) == left)
    }
}
