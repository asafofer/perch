import Testing
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
@testable import PerchCore

@Suite struct ScreenTargetTests {
    let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let lg = CGRect(x: 1512, y: 0, width: 2560, height: 1440)
    var frames: [CGRect] { [laptop, lg] }
    let ids = ["A", "B"]

    func pick(_ c: ShowOn, mouse: CGPoint, window: CGRect? = nil) -> Int? {
        ScreenTarget.index(for: c, displayIDs: ids, frames: frames, mouse: mouse, window: window)
    }

    @Test func rawRoundTrips() {
        #expect(ShowOn(raw: "mouse") == .mouse)
        #expect(ShowOn(raw: "window") == .window)
        #expect(ShowOn(raw: "B") == .display("B"))
        #expect(ShowOn(raw: "") == .mouse)
        #expect(ShowOn.display("B").raw == "B")
    }
    @Test func mouseModeFollowsTheCursor() {
        #expect(pick(.mouse, mouse: CGPoint(x: 2000, y: 500)) == 1)
        #expect(pick(.mouse, mouse: CGPoint(x: 700, y: 982)) == 0)   // resting on the laptop's top edge, aiming at the notch
    }
    @Test func windowModePicksTheScreenHoldingMostOfIt() {
        #expect(pick(.window, mouse: CGPoint(x: 100, y: 100), window: CGRect(x: 1400, y: 100, width: 800, height: 600)) == 1)
    }
    @Test func windowModeWithNoWindowFollowsMouse() {
        #expect(pick(.window, mouse: CGPoint(x: 100, y: 100)) == 0)
        #expect(pick(.window, mouse: CGPoint(x: 2000, y: 500), window: CGRect(x: 9000, y: 9000, width: 10, height: 10)) == 1)
    }
    @Test func displayModeIgnoresTheMouse() {
        #expect(pick(.display("A"), mouse: CGPoint(x: 2000, y: 500)) == 0)
    }
    @Test func missingDisplayFollowsMouse() {
        #expect(pick(.display("Z"), mouse: CGPoint(x: 2000, y: 500)) == 1)
    }
    @Test func mouseOffEveryScreenIsNil() {
        #expect(pick(.mouse, mouse: CGPoint(x: -500, y: -500)) == nil)
    }
    @Test func cocoaRectFlipsY() {
        #expect(ScreenTarget.cocoaRect(fromCG: CGRect(x: 100, y: 50, width: 400, height: 300), primaryHeight: 982) == CGRect(x: 100, y: 632, width: 400, height: 300))
    }
    @Test func hoverRectMatchesTheOldZone() {
        let notched = ScreenInfo(frame: laptop, notchSize: CGSize(width: 185, height: 32))
        #expect(NotchGeometry.hoverRect(for: notched) == CGRect(x: 633.5, y: 948, width: 223, height: 72))
    }
    @Test func detourStaysWhileTheCursorIsOnTheActivity() {
        let zone = CGRect(x: 633.5, y: 948, width: 223, height: 72), activity = CGRect(x: 556, y: 862, width: 400, height: 120)
        #expect(HoverDetour.goBack(at: CGPoint(x: 756, y: 900), zone: zone, activity: activity) == false)   // below the zone, on the activity's buttons
        #expect(HoverDetour.goBack(at: CGPoint(x: 756, y: 900), zone: zone, activity: nil))
        #expect(HoverDetour.goBack(at: CGPoint(x: 756, y: 960), zone: zone, activity: nil) == false)
    }
    @Test func detourWaitsForTheDwellWhileAnActivityShows() {
        let t = Date(timeIntervalSince1970: 1000)
        #expect(HoverDetour.leave(enteredAt: t, now: t, activityShowing: false))
        #expect(HoverDetour.leave(enteredAt: t, now: t.addingTimeInterval(0.1), activityShowing: true) == false)
        #expect(HoverDetour.leave(enteredAt: t, now: t.addingTimeInterval(0.25), activityShowing: true))
    }
    @Test func hoverZoneNeedsTheCursorOnThatScreen() {
        let top = CGRect(x: 0, y: 982, width: 1512, height: 982)   // a display stacked above the laptop
        let frames2 = [laptop, top]
        let rect = NotchGeometry.hoverRect(for: ScreenInfo(frame: laptop, notchSize: CGSize(width: 185, height: 32)))
        #expect(NotchGeometry.hovering(CGPoint(x: 756, y: 990), frames: frames2, index: 0, rect: rect) == false)
        #expect(NotchGeometry.hovering(CGPoint(x: 756, y: 970), frames: frames2, index: 0, rect: rect))
    }
}
