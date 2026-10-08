import CoreGraphics

/// Screen facts the geometry needs, so it can be tested without a real display.
public struct ScreenInfo: Equatable, Sendable {
    public var frame: CGRect          // screen frame in global coordinates (origin bottom-left)
    public var notchSize: CGSize?     // hardware notch size, nil on Macs without one
    public var menuBarHeight: CGFloat // height of the menu bar here; sizes the stand-in tab on screens without a notch
    public init(frame: CGRect, notchSize: CGSize?, menuBarHeight: CGFloat = 24) { self.frame = frame; self.notchSize = notchSize; self.menuBarHeight = menuBarHeight }
}

public enum NotchGeometry {
    public static let cardWidth: CGFloat = 400
    /// One fixed, transparent panel hosts every phase. It holds the tallest card plus room for the shadow.
    public static let panelSize = CGSize(width: 480, height: 320)
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
               width: panelSize.width, height: panelSize.height)
    }

    /// Screen-space rect of the visible card, used for hover and click-through. `height` comes from the UI.
    public static func contentRect(width: CGFloat, height: CGFloat, screen: ScreenInfo) -> CGRect {
        CGRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height)
    }
}
