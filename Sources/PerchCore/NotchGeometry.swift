import CoreGraphics

/// Screen facts the geometry needs, so it can be tested without a real display.
public struct ScreenInfo: Equatable, Sendable {
    public var frame: CGRect          // screen frame in global coordinates (origin bottom-left)
    public var notchSize: CGSize?     // hardware notch size, nil on Macs without one
    public var menuBarHeight: CGFloat // height of the menu bar here; sizes the stand-in tab on screens without a notch
    public var fullScreen: Bool       // an app is full screen here: a display without a notch then shows nothing at rest
    public init(frame: CGRect, notchSize: CGSize?, menuBarHeight: CGFloat = 24, fullScreen: Bool = false) { self.frame = frame; self.notchSize = notchSize; self.menuBarHeight = menuBarHeight; self.fullScreen = fullScreen }
}

public enum NotchGeometry {
    public static let cardWidth: CGFloat = 400
    /// One fixed, transparent panel hosts every phase. It holds the tallest card plus room for the shadow.
    public static let panelSize = CGSize(width: 480, height: 410)
    /// The panel reaches this far above the top of the screen, and the card draws a black cap into it,
    /// so a rounding gap or a slight offset can never show the desktop above an open card.
    public static let overscan: CGFloat = 10
    public static let fallbackIdleHeight: CGFloat = 32

    /// Width of the stand-in tab drawn where a notch would be, on a screen without one.
    public static let tabWidth: CGFloat = 148

    /// Idle footprint: the hardware notch, or a small black tab in the menu bar on a screen without one.
    public static func idleSize(for screen: ScreenInfo) -> CGSize {
        screen.notchSize ?? CGSize(width: tabWidth, height: min(max(screen.menuBarHeight, 22), 28))
    }

    /// The panel, top-centred on the screen.
    public static func panelFrame(for screen: ScreenInfo) -> CGRect {
        CGRect(x: screen.frame.midX - panelSize.width / 2, y: screen.frame.maxY - panelSize.height,
               width: panelSize.width, height: panelSize.height + overscan)
    }

    /// Where resting the cursor opens Perch: the notch plus a little room for the character beside it (wider while the
    /// wings show). Extends above the screen edge so the very top pixel row of the cursor counts.
    public static func hoverRect(for screen: ScreenInfo, wingsWidth: CGFloat = 0) -> CGRect {
        let idle = idleSize(for: screen)
        let w = max(idle.width, 150, wingsWidth)
        let left: CGFloat = 30, right: CGFloat = 8     // the character sits just left of the notch
        return CGRect(x: screen.frame.midX - w / 2 - left, y: screen.frame.maxY - idle.height - 2, width: w + left + right, height: idle.height + 40)
    }

    /// On a screen without a notch, a small black pill with your character rests at the top centre, in the menu bar with
    /// the same gap above and below it. The bar's last point is its hairline, so the band you see is one point shorter
    /// than the height macOS reports (measured on a 1x display: 30 reported, 29 of bar, then the line). The pill is 18 or
    /// 19 tall, whichever leaves a whole-point gap on both sides, so neither edge lands on half a pixel.
    public static let pillWidth: CGFloat = 30
    public static func pill(for screen: ScreenInfo) -> (top: CGFloat, size: CGSize) {
        let band = max(20, (screen.menuBarHeight - 1).rounded())
        let h: CGFloat = band.truncatingRemainder(dividingBy: 2) == 0 ? 18 : 19
        return ((band - h) / 2, CGSize(width: pillWidth, height: h))
    }

    /// Where resting the cursor on that pill opens Perch: the pill with a little slack round it, up past the top edge so
    /// the cursor parked on it (y == maxY) counts.
    public static func pillHoverRect(for screen: ScreenInfo) -> CGRect {
        let p = pill(for: screen), slack: CGFloat = 6, w = p.size.width + slack * 2, below = p.top + p.size.height + slack
        return CGRect(x: screen.frame.midX - w / 2, y: screen.frame.maxY - below, width: w, height: below + 2)
    }

    /// The cursor is in that screen's hover zone. The zone reaches above its screen's edge, so a display stacked above
    /// must not count: the cursor has to be on screen `i` itself.
    public static func hovering(_ p: CGPoint, frames: [CGRect], index i: Int, rect: CGRect) -> Bool {
        rect.contains(p) && ScreenPicker.index(of: p, in: frames) == i
    }

    /// Screen-space rect of the visible card, used for hover and click-through. `height` comes from the UI.
    public static func contentRect(width: CGFloat, height: CGFloat, screen: ScreenInfo) -> CGRect {
        CGRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height)
    }
}

public enum ScreenPicker {
    /// Which of these screen frames the cursor is on. CGRect.contains leaves out the top and right edges, but the cursor
    /// rests exactly on the top edge of a screen (y == maxY) when you aim at a notch, so a screen that holds the point
    /// strictly wins, and failing that one whose edge the point sits on. Nil when it is on none of them.
    public static func index(of point: CGPoint, in frames: [CGRect]) -> Int? {
        if let i = frames.firstIndex(where: { $0.contains(point) }) { return i }
        return frames.firstIndex { point.x >= $0.minX && point.x <= $0.maxX && point.y >= $0.minY && point.y <= $0.maxY }
    }
}
