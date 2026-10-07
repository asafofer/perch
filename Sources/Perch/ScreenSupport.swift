import AppKit
import PerchCore

extension NSScreen {
    /// Hardware notch size, or nil when this display has none.
    var notchSize: CGSize? {
        guard safeAreaInsets.top > 0,
              let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea else { return nil }
        return CGSize(width: frame.width - left.width - right.width, height: safeAreaInsets.top)
    }
    var screenInfo: ScreenInfo { ScreenInfo(frame: frame, notchSize: notchSize) }
}

enum ScreenChooser {
    /// Where the notch lives when nothing is showing: the built-in display with a notch, else the main display.
    static func home() -> NSScreen {
        NSScreen.screens.first { $0.notchSize != nil } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// The display under the cursor, else the built-in one, else the main one.
    static func current() -> NSScreen {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(p) }
            ?? NSScreen.screens.first { $0.notchSize != nil }
            ?? NSScreen.main ?? NSScreen.screens[0]
    }
}
