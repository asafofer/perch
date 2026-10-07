import CoreGraphics

/// Screen facts the geometry needs, so it can be tested without a real display.
public struct ScreenInfo: Equatable, Sendable {
    public var frame: CGRect          // screen frame in global coordinates (origin bottom-left)
    public var notchSize: CGSize?     // hardware notch size, nil on Macs without one
    public init(frame: CGRect, notchSize: CGSize?) { self.frame = frame; self.notchSize = notchSize }
}

public enum NotchGeometry {
    public static let fallbackPillSize = CGSize(width: 188, height: 34)
    public static let openSize = CGSize(width: 600, height: 224)
    public static let switcherSize = CGSize(width: 600, height: 238)
    public static let restoringSize = CGSize(width: 600, height: 200)
    /// Transparent margin around the largest card, so shadows are not clipped.
    public static let shadowMargin: CGFloat = 40

    public static func idleSize(for screen: ScreenInfo) -> CGSize {
        screen.notchSize ?? fallbackPillSize
    }

    public static func size(for phase: NotchPhase, screen: ScreenInfo) -> CGSize {
        switch phase {
        case .idle: idleSize(for: screen)
        case .open: openSize
        case .switcher: switcherSize
        case .restoring: restoringSize
        }
    }

    /// The fixed panel that hosts every phase: top-centred, big enough for the largest card plus margin.
    public static func panelFrame(for screen: ScreenInfo) -> CGRect {
        let w = openSize.width + shadowMargin * 2
        let h = openSize.height + shadowMargin
        return CGRect(x: screen.frame.midX - w / 2, y: screen.frame.maxY - h, width: w, height: h)
    }

    /// Screen-space rect of the visible card for a phase (used for hover and click-through).
    public static func contentRect(for phase: NotchPhase, screen: ScreenInfo) -> CGRect {
        let s = size(for: phase, screen: screen)
        return CGRect(x: screen.frame.midX - s.width / 2, y: screen.frame.maxY - s.height, width: s.width, height: s.height)
    }
}
