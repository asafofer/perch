import CPerchLinux
import Foundation

/// The X server, as GDK opened it, and the EWMH properties window managers keep (_NET_ACTIVE_WINDOW, _NET_WM_PID ...).
/// Everything Perch reads about other apps' windows comes through here. Main thread only: Xlib's connection is GDK's.
enum X11 {
    static var display: OpaquePointer? { gdk_x11_display_get_xdisplay(gdk_display_get_default()) }
    static var root: Window { display.map { XDefaultRootWindow($0) } ?? 0 }

    static func atom(_ name: String) -> Atom { display.map { XInternAtom($0, name, 0) } ?? 0 }

    /// A window's property as 32-bit items (X returns them as longs).
    static func cardinals(_ w: Window, _ name: String, type: Atom = Atom(XA_CARDINAL)) -> [UInt] {
        guard let d = display else { return [] }
        var actual: Atom = 0, format: Int32 = 0, n: UInt = 0, after: UInt = 0
        var data: UnsafeMutablePointer<UInt8>?
        guard XGetWindowProperty(d, w, atom(name), 0, 1024, 0, type, &actual, &format, &n, &after, &data) == Success, let data else { return [] }
        defer { XFree(data) }
        guard format == 32 else { return [] }
        return data.withMemoryRebound(to: UInt.self, capacity: Int(n)) { Array(UnsafeBufferPointer(start: $0, count: Int(n))) }
    }

    /// A window's property as text (UTF8_STRING or STRING), with NUL-separated parts.
    static func strings(_ w: Window, _ name: String) -> [String] {
        guard let d = display else { return [] }
        var actual: Atom = 0, format: Int32 = 0, n: UInt = 0, after: UInt = 0
        var data: UnsafeMutablePointer<UInt8>?
        guard XGetWindowProperty(d, w, atom(name), 0, 4096, 0, Atom(AnyPropertyType), &actual, &format, &n, &after, &data) == Success, let data else { return [] }
        defer { XFree(data) }
        guard format == 8 else { return [] }
        let bytes = Array(UnsafeBufferPointer(start: data, count: Int(n)))
        return bytes.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
    }

    /// The window the window manager says is active, if any.
    static func activeWindow() -> Window? {
        cardinals(root, "_NET_ACTIVE_WINDOW", type: Atom(XA_WINDOW)).first.flatMap { $0 == 0 ? nil : Window($0) }
    }
    static func pid(of w: Window) -> pid_t? { cardinals(w, "_NET_WM_PID").first.map { pid_t($0) } }
    /// WM_CLASS's class part, lowercased: Linux's nearest thing to a bundle id ("xfce4-terminal", "kitty", "code").
    static func appId(of w: Window) -> String? { strings(w, "WM_CLASS").last?.lowercased() }
    static func title(of w: Window) -> String? { strings(w, "_NET_WM_NAME").first ?? strings(w, "WM_NAME").first }
    /// Top-level windows the window manager manages, bottom to top.
    /// Some window managers (xfwm4 4.16) keep no stacking list: then the plain client list, in mapping order.
    static func clientWindows() -> [Window] {
        let stacked = cardinals(root, "_NET_CLIENT_LIST_STACKING", type: Atom(XA_WINDOW))
        return (stacked.isEmpty ? cardinals(root, "_NET_CLIENT_LIST", type: Atom(XA_WINDOW)) : stacked).map { Window($0) }
    }

    /// Asks the window manager to bring a window forward and give it the keyboard (source 2: a pager, which WMs obey
    /// without focus-stealing checks).
    static func activate(_ w: Window) {
        guard let d = display else { return }
        if let desk = cardinals(w, "_NET_WM_DESKTOP").first, desk != 0xFFFFFFFF { clientMessage(root, "_NET_CURRENT_DESKTOP", [Int(desk), 0, 0, 0, 0]) }
        clientMessage(w, "_NET_ACTIVE_WINDOW", [2, 0, 0, 0, 0])
        XFlush(d)
    }

    static func clientMessage(_ w: Window, _ type: String, _ data: [Int]) {
        guard let d = display else { return }
        var e = XEvent()
        e.xclient.type = ClientMessage
        e.xclient.window = w
        e.xclient.message_type = atom(type)
        e.xclient.format = 32
        withUnsafeMutableBytes(of: &e.xclient.data.l) { buf in
            let longs = buf.bindMemory(to: Int.self)
            for (i, v) in data.prefix(5).enumerated() { longs[i] = v }
        }
        XSendEvent(d, root, 0, SubstructureRedirectMask | SubstructureNotifyMask, &e)
    }

    /// The pointer, in X's coordinates (top left origin).
    static func pointer() -> CGPoint {
        guard let d = display else { return .zero }
        var r: Window = 0, c: Window = 0, rx: Int32 = 0, ry: Int32 = 0, wx: Int32 = 0, wy: Int32 = 0, mask: UInt32 = 0
        XQueryPointer(d, root, &r, &c, &rx, &ry, &wx, &wy, &mask)
        return CGPoint(x: Int(rx), y: Int(ry))
    }

    /// The root window's size: the height turns X's top-left coordinates into Cocoa's bottom-left ones, which the shared
    /// geometry (NotchGeometry, ScreenTarget) is written in.
    static var rootSize: CGSize {
        guard let d = display else { return .zero }
        let s = XDefaultScreen(d)
        return CGSize(width: Int(XDisplayWidth(d, s)), height: Int(XDisplayHeight(d, s)))
    }
    /// A rect in X's coordinates to Cocoa's, and back (the same flip both ways).
    static func flip(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: rootSize.height - r.maxY, width: r.width, height: r.height) }
    static func flip(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: rootSize.height - p.y) }
}
