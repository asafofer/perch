import CPerchLinux
import Foundation

/// Perch's own connection to the X server, for reading and raising other apps' windows from any thread. GDK's connection
/// (X11.display) belongs to the main thread; this one is opened on first use and used under a lock. Xlib needs
/// XInitThreads before any connection is opened for two connections to be used from two threads.
final class XServer: @unchecked Sendable {
    static let shared = XServer()

    /// A top-level window the window manager manages.
    struct Win: Equatable {
        let id: Window
        let pid: pid_t?
        /// WM_CLASS's class part, lowercased (X11.appId).
        let app: String?
        let title: String
    }

    private let lock = NSLock()
    private var opened = false
    private var d: OpaquePointer?
    private var atoms: [String: Atom] = [:]

    /// Runs `body` with the connection, under the lock. Nil when there is no X server to talk to.
    private func with<T>(_ body: (OpaquePointer) -> T) -> T? {
        lock.lock(); defer { lock.unlock() }
        if !opened { opened = true; d = XOpenDisplay(nil) }
        guard let d else { return nil }
        return body(d)
    }

    private func atom(_ d: OpaquePointer, _ name: String) -> Atom {
        if let a = atoms[name] { return a }
        let a = XInternAtom(d, name, 0)
        atoms[name] = a
        return a
    }

    /// The managed windows, bottom to top.
    func windows() -> [Win] {
        with { d in
            let root = XDefaultRootWindow(d)
            return cardinals(d, root, "_NET_CLIENT_LIST_STACKING", type: Atom(XA_WINDOW)).map { w in
                let w = Window(w)
                return Win(id: w, pid: cardinals(d, w, "_NET_WM_PID").first.map { pid_t($0) },
                           app: strings(d, w, "WM_CLASS").last?.lowercased(),
                           title: strings(d, w, "_NET_WM_NAME").first ?? strings(d, w, "WM_NAME").first ?? "")
            }
        } ?? []
    }

    /// The window the window manager says is active.
    func active() -> Window? {
        with { d in cardinals(d, XDefaultRootWindow(d), "_NET_ACTIVE_WINDOW", type: Atom(XA_WINDOW)).first.flatMap { $0 == 0 ? nil : Window($0) } } ?? nil
    }

    /// Brings a window forward with the keyboard, on its own desktop (as X11.activate does).
    func activate(_ w: Window) {
        _ = with { d in
            let root = XDefaultRootWindow(d)
            if let desk = cardinals(d, w, "_NET_WM_DESKTOP").first, desk != 0xFFFFFFFF { message(d, root, "_NET_CURRENT_DESKTOP", [Int(desk), 0, 0, 0, 0]) }
            message(d, w, "_NET_ACTIVE_WINDOW", [2, 0, 0, 0, 0])
            XFlush(d)
        }
    }

    /// The text on the clipboard, asked of its owner directly, waiting at most `timeout`. Nil when there is none, when it
    /// is not text, or when the owner does not answer in time. An owner on GDK's own connection (Perch) cannot answer while
    /// the main thread waits here, so the caller handles that case itself.
    func clipboardText(timeout: TimeInterval = 0.4) -> String? {
        with { d -> String? in
            let clip = atom(d, "CLIPBOARD"), utf8 = atom(d, "UTF8_STRING"), prop = atom(d, "PERCH_CLIP"), incr = atom(d, "INCR")
            guard XGetSelectionOwner(d, clip) != 0 else { return nil }
            let win = XCreateSimpleWindow(d, XDefaultRootWindow(d), 0, 0, 1, 1, 0, 0, 0)
            defer { XDestroyWindow(d, win); XFlush(d) }
            XSelectInput(d, win, PropertyChangeMask)
            XConvertSelection(d, clip, utf8, prop, win, UInt(CurrentTime))
            XFlush(d)
            let end = Date().addingTimeInterval(timeout)
            var e = XEvent()
            func wait(_ type: Int32) -> Bool {
                while Date() < end {
                    if XCheckTypedWindowEvent(d, win, type, &e) != 0 {
                        if type == PropertyNotify, e.xproperty.atom != prop || e.xproperty.state != PropertyNewValue { continue }
                        return true
                    }
                    usleep(5000)
                }
                return false
            }
            guard wait(SelectionNotify), e.xselection.property != 0 else { return nil }
            guard let (type, first) = take(d, win, prop) else { return nil }
            if type != incr { return String(decoding: first, as: UTF8.self) }
            // Large text comes in parts: each one put on the property, taken, until an empty one.
            var all = Data()
            while wait(PropertyNotify), let (_, part) = take(d, win, prop) {
                if part.isEmpty { return String(decoding: all, as: UTF8.self) }
                all.append(part)
            }
            return nil
        } ?? nil
    }

    // MARK: Xlib, on this connection

    /// A property read and deleted (which tells the owner it was taken): its type and bytes.
    private func take(_ d: OpaquePointer, _ w: Window, _ prop: Atom) -> (Atom, Data)? {
        var actual: Atom = 0, format: Int32 = 0, n: UInt = 0, after: UInt = 0
        var data: UnsafeMutablePointer<UInt8>?
        guard XGetWindowProperty(d, w, prop, 0, 0x1FFFFFFF, 1, Atom(AnyPropertyType), &actual, &format, &n, &after, &data) == Success else { return nil }
        defer { if let data { XFree(data) } }
        let size = format == 32 ? Int(n) * MemoryLayout<UInt>.size : format == 16 ? Int(n) * 2 : Int(n)
        return (actual, data.map { Data(bytes: $0, count: size) } ?? Data())
    }

    private func cardinals(_ d: OpaquePointer, _ w: Window, _ name: String, type: Atom = Atom(XA_CARDINAL)) -> [UInt] {
        var actual: Atom = 0, format: Int32 = 0, n: UInt = 0, after: UInt = 0
        var data: UnsafeMutablePointer<UInt8>?
        guard XGetWindowProperty(d, w, atom(d, name), 0, 4096, 0, type, &actual, &format, &n, &after, &data) == Success, let data else { return [] }
        defer { XFree(data) }
        guard format == 32 else { return [] }
        return data.withMemoryRebound(to: UInt.self, capacity: Int(n)) { Array(UnsafeBufferPointer(start: $0, count: Int(n))) }
    }

    private func strings(_ d: OpaquePointer, _ w: Window, _ name: String) -> [String] {
        var actual: Atom = 0, format: Int32 = 0, n: UInt = 0, after: UInt = 0
        var data: UnsafeMutablePointer<UInt8>?
        guard XGetWindowProperty(d, w, atom(d, name), 0, 4096, 0, Atom(AnyPropertyType), &actual, &format, &n, &after, &data) == Success, let data else { return [] }
        defer { XFree(data) }
        guard format == 8 else { return [] }
        return Array(UnsafeBufferPointer(start: data, count: Int(n))).split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
    }

    private func message(_ d: OpaquePointer, _ w: Window, _ type: String, _ data: [Int]) {
        var e = XEvent()
        e.xclient.type = ClientMessage
        e.xclient.window = w
        e.xclient.message_type = atom(d, type)
        e.xclient.format = 32
        withUnsafeMutableBytes(of: &e.xclient.data.l) { buf in
            let longs = buf.bindMemory(to: Int.self)
            for (i, v) in data.prefix(5).enumerated() { longs[i] = v }
        }
        XSendEvent(d, XDefaultRootWindow(d), 0, SubstructureRedirectMask | SubstructureNotifyMask, &e)
    }
}
