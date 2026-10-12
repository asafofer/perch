import CPerchLinux
import Foundation
import PerchCore

/// A display, as GDK sees it, in Cocoa's coordinates (bottom-left origin) like NSScreen, in X's device pixels like
/// everything Perch places (Panel.setFrame). No Linux display has a notch: Perch rests there as it does on a Mac's
/// external display.
struct Screen: Equatable {
    let frame: CGRect
    /// The part panels leave free, from their struts, Cocoa coordinates.
    let visibleFrame: CGRect
    let localizedName: String
    /// The connector ("eDP-1", "HDMI-1"): stays the same while the display is plugged into the same port.
    let displayID: String
    /// GDK's scale for this display (2 on a HiDPI one with GDK_SCALE=2 or Xft.dpi 192). X has one scale for the whole
    /// screen, so every display reports the same.
    var scale: CGFloat = 1

    /// The top panel's height on this display (0 with none there).
    var menuBarHeight: CGFloat { max(0, frame.maxY - visibleFrame.maxY) }
    var screenInfo: ScreenInfo { ScreenInfo(frame: frame, notchSize: nil, menuBarHeight: menuBarHeight > 0 ? menuBarHeight : 24) }

    static var screens: [Screen] {
        guard let display = gdk_display_get_default(), let list = gdk_display_get_monitors(display) else { return [] }
        let root = X11.rootSize
        let struts = Struts.current()
        var out: [Screen] = []
        for i in 0..<g_list_model_get_n_items(list) {
            guard let item = g_list_model_get_item(list, i) else { continue }
            defer { g_object_unref(item) }
            let monitor = OpaquePointer(item)
            var g = GdkRectangle()
            gdk_monitor_get_geometry(monitor, &g)
            // GDK gives application pixels; X places windows in device pixels.
            let scale = CGFloat(gdk_monitor_get_scale_factor(monitor))
            let x = CGRect(x: CGFloat(g.x) * scale, y: CGFloat(g.y) * scale, width: CGFloat(g.width) * scale, height: CGFloat(g.height) * scale)
            let visible = struts.map { PanelStruts.free(x, root: root, struts: $0) } ?? Struts.workArea(x)
            let connector = gdk_monitor_get_connector(monitor).map { String(cString: $0) } ?? "screen\(i)"
            let model = gdk_monitor_get_model(monitor).map { String(cString: $0) }
            out.append(Screen(frame: X11.flip(x), visibleFrame: X11.flip(visible), localizedName: model ?? connector, displayID: connector, scale: scale))
        }
        return out
    }
    /// The primary display (RandR's primary output), else the one at X's origin, else the first.
    static var main: Screen? {
        let all = screens
        if let display = gdk_display_get_default(), let primary = gdk_x11_display_get_primary_monitor(display),
           let connector = gdk_monitor_get_connector(primary).map({ String(cString: $0) }), let s = all.first(where: { $0.displayID == connector }) { return s }
        return all.first { X11.flip($0.frame).origin == .zero } ?? all.first
    }
}

/// What panels reserve at the screen's edges (_NET_WM_STRUT_PARTIAL, else _NET_WM_STRUT, on each managed window), so
/// each display's free part is its own: _NET_WORKAREA is one rectangle for all displays and cuts the wrong ones.
/// Read at most every two seconds: it asks every window. Main thread, like all of X11's reads.
enum Struts {
    nonisolated(unsafe) private static var cache: (at: Date, struts: [[UInt]]?) = (.distantPast, nil)

    /// Each panel's twelve numbers (left, right, top, bottom, then the start and end of each along its edge), or nil
    /// when the window manager lists no windows (then _NET_WORKAREA stands in).
    static func current() -> [[UInt]]? {
        if Date().timeIntervalSince(cache.at) < 2 { return cache.struts }
        let windows = Quiet.managedWindows()
        var out: [[UInt]]? = windows.isEmpty ? nil : []
        for w in windows {
            let p = X11.cardinals(w, "_NET_WM_STRUT_PARTIAL")
            if p.count >= 12, p[0...3].contains(where: { $0 > 0 }) { out?.append(Array(p.prefix(12))); continue }
            let s = X11.cardinals(w, "_NET_WM_STRUT")
            if s.count >= 4, s.contains(where: { $0 > 0 }) { out?.append(s.prefix(4) + [0, .max, 0, .max, 0, .max, 0, .max]) }
        }
        cache = (Date(), out)
        return out
    }

    /// Without a window list: the window manager's _NET_WORKAREA over this display, else all of it.
    static func workArea(_ m: CGRect) -> CGRect {
        let work = X11.cardinals(X11.root, "_NET_WORKAREA")
        guard work.count >= 4 else { return m }
        let r = CGRect(x: Int(work[0]), y: Int(work[1]), width: Int(work[2]), height: Int(work[3])).intersection(m)
        return r.isNull || r.isEmpty ? m : r
    }
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
