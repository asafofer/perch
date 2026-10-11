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
    /// This display's own id, the same across reboots and ports: its UUID, else its display number for one without.
    var displayID: String {
        let number = (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        if let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue(), let s = CFUUIDCreateString(nil, uuid) { return s as String }
        return "id:\(number)"
    }
}

/// The front window of the app in front, from the window list (its bounds need no permission). Nil on the desktop, for
/// an app with no window, or when Perch itself is in front.
enum FrontWindow {
    static func frame() -> CGRect? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier, pid != ProcessInfo.processInfo.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let primary = NSScreen.screens.first else { return nil }
        for w in list where (w[kCGWindowOwnerPID as String] as? Int32) == pid && (w[kCGWindowLayer as String] as? Int) == 0 {
            guard let b = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: b), r.width >= 50, r.height >= 50 else { continue }
            return ScreenTarget.cocoaRect(fromCG: r, primaryHeight: primary.frame.height)
        }
        return nil
    }
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

    /// Where the shortcut opens Perch and where it shows up by itself, as Show Perch on says.
    static func target() -> NSScreen {
        let screens = NSScreen.screens, choice = Prefs.showOn
        let i = ScreenTarget.index(for: choice, displayIDs: screens.map(\.displayID), frames: screens.map(\.frame),
                                   mouse: NSEvent.mouseLocation, window: choice == .window ? FrontWindow.frame() : nil)
        return i.map { screens[$0] } ?? current()
    }

    /// Where the panel waits while nothing is open: with the mouse it follows the cursor, as it always did; otherwise it
    /// waits on the target, so a live activity grows there.
    static func rest() -> NSScreen {
        Prefs.showOn == .mouse ? current() : target()
    }
}
