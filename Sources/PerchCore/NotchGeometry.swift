import CoreGraphics

/// Screen facts the geometry needs, so it can be tested without a real display.
public struct ScreenInfo: Equatable, Sendable {
    public var frame: CGRect          // screen frame in global coordinates (origin bottom-left)
    public var notchSize: CGSize?     // hardware notch size, nil on Macs without one
    public init(frame: CGRect, notchSize: CGSize?) { self.frame = frame; self.notchSize = notchSize }
}

public enum NotchGeometry {
    public static let cardWidth: CGFloat = 360
    /// One fixed, transparent panel hosts every phase. It holds the tallest card plus room for the shadow.
    public static let panelSize = CGSize(width: 440, height: 300)
    public static let fallbackIdleHeight: CGFloat = 32

    /// Idle footprint: the hardware notch, or nothing visible on a Mac without one.
    public static func idleSize(for screen: ScreenInfo) -> CGSize {
        screen.notchSize ?? CGSize(width: 0, height: fallbackIdleHeight)
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
