import CPerchLinux
import Foundation
import PerchCore

/// A display, as GDK sees it, in Cocoa's coordinates (bottom-left origin) like NSScreen. No Linux display has a notch:
/// Perch rests there as it does on a Mac's external display.
struct Screen: Equatable {
    let frame: CGRect
    /// The part not taken by panels (_NET_WORKAREA), Cocoa coordinates.
    let visibleFrame: CGRect
    let localizedName: String
    /// The connector ("eDP-1", "HDMI-1"): stays the same while the display is plugged into the same port.
    let displayID: String

    var menuBarHeight: CGFloat { max(0, frame.maxY - visibleFrame.maxY) }
    var screenInfo: ScreenInfo { ScreenInfo(frame: frame, notchSize: nil, menuBarHeight: menuBarHeight > 0 ? menuBarHeight : 24) }

    static var screens: [Screen] {
        guard let display = gdk_display_get_default(), let list = gdk_display_get_monitors(display) else { return [] }
        let work = X11.cardinals(X11.root, "_NET_WORKAREA")
        let workArea = work.count >= 4 ? CGRect(x: Int(work[0]), y: Int(work[1]), width: Int(work[2]), height: Int(work[3])) : nil
        var out: [Screen] = []
        for i in 0..<g_list_model_get_n_items(list) {
            guard let item = g_list_model_get_item(list, i) else { continue }
            defer { g_object_unref(item) }
            let monitor = OpaquePointer(item)
            var g = GdkRectangle()
            gdk_monitor_get_geometry(monitor, &g)
            let scale = CGFloat(gdk_monitor_get_scale_factor(monitor))
            let x = CGRect(x: CGFloat(g.x) * scale, y: CGFloat(g.y) * scale, width: CGFloat(g.width) * scale, height: CGFloat(g.height) * scale)
            // _NET_WORKAREA spans every monitor; the part over this one is what panels leave of it.
            let visible = workArea.map { $0.intersection(x) }.flatMap { $0.isNull || $0.isEmpty ? nil : $0 } ?? x
            let connector = gdk_monitor_get_connector(monitor).map { String(cString: $0) } ?? "screen\(i)"
            let model = gdk_monitor_get_model(monitor).map { String(cString: $0) }
            out.append(Screen(frame: X11.flip(x), visibleFrame: X11.flip(visible), localizedName: model ?? connector, displayID: connector))
        }
        return out
    }
    /// The primary display: the one at X's origin, else the first.
    static var main: Screen? { let all = screens; return all.first { X11.flip($0.frame).origin == .zero } ?? all.first }
}

enum Mouse {
    /// The pointer in Cocoa's coordinates (NSEvent.mouseLocation).
    static var location: CGPoint { X11.flip(X11.pointer()) }
}

enum FrontWindow {
    /// The active window's frame, Cocoa coordinates, unless it is Perch's own or too small to be a real window.
    static func frame() -> CGRect? {
        guard let d = X11.display, let w = X11.activeWindow(), X11.pid(of: w) != getpid() else { return nil }
        var attrs = XWindowAttributes()
        guard XGetWindowAttributes(d, w, &attrs) != 0, attrs.width >= 50, attrs.height >= 50 else { return nil }
        var x: Int32 = 0, y: Int32 = 0, child: Window = 0
        XTranslateCoordinates(d, w, X11.root, 0, 0, &x, &y, &child)
        return X11.flip(CGRect(x: Int(x), y: Int(y), width: Int(attrs.width), height: Int(attrs.height)))
    }
}

/// Which display Perch shows on: the same choices as the Mac's (ScreenSupport.swift there).
enum ScreenChooser {
    private static var fallback: Screen {
        Screen(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080), localizedName: "Display", displayID: "none")
    }
    /// Where Perch rests when nothing is showing: the primary display.
    static func home() -> Screen { Screen.main ?? fallback }

    /// The display the cursor is on, the top row included, else nil.
    static func under(_ p: CGPoint = Mouse.location) -> Screen? {
        let screens = Screen.screens
        return ScreenPicker.index(of: p, in: screens.map(\.frame)).map { screens[$0] }
    }

    static func current() -> Screen { under() ?? home() }

    static func target() -> Screen {
        let screens = Screen.screens, choice = Prefs.showOn
        let i = ScreenTarget.index(for: choice, displayIDs: screens.map(\.displayID), frames: screens.map(\.frame),
                                   mouse: Mouse.location, window: choice == .window ? FrontWindow.frame() : nil)
        return i.map { screens[$0] } ?? current()
    }

    static func rest() -> Screen { Prefs.showOn == .mouse ? current() : target() }
}
