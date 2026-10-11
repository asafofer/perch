import AppKit
import PerchCore

extension NSScreen {
    /// Hardware notch size, or nil when this display has none.
    var notchSize: CGSize? {
        guard safeAreaInsets.top > 0,
              let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea else { return nil }
        return CGSize(width: frame.width - left.width - right.width, height: safeAreaInsets.top)
    }
    /// The menu bar's height on this display (0 when it hides itself, so a default is used).
    var menuBarHeight: CGFloat { max(0, frame.maxY - visibleFrame.maxY) }
    var screenInfo: ScreenInfo { ScreenInfo(frame: frame, notchSize: notchSize, menuBarHeight: menuBarHeight > 0 ? menuBarHeight : 24) }
}

enum ScreenChooser {
    /// Where the notch lives when nothing is showing: the built-in display with a notch, else the main display.
    static func home() -> NSScreen {
        NSScreen.screens.first { $0.notchSize != nil } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// The display the cursor is on, the top row included (that is where you aim at a notch), else nil.
    static func under(_ p: CGPoint = NSEvent.mouseLocation) -> NSScreen? {
        let screens = NSScreen.screens
        return ScreenPicker.index(of: p, in: screens.map(\.frame)).map { screens[$0] }
    }

    /// The display under the cursor, else the built-in one, else the main one.
    static func current() -> NSScreen {
        under() ?? NSScreen.screens.first { $0.notchSize != nil } ?? NSScreen.main ?? NSScreen.screens[0]
    }
}
