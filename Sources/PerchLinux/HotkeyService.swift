import CPerchLinux
import Foundation
import PerchCore

/// Global shortcuts on X11. A key combo is a passive grab on the root window (XGrabKey); the tap that opens Perch is read
/// from XInput2 raw key events, which every client may select and which arrive even while another app holds a grab.
/// Neither needs a permission. Key codes and modifiers stay in the Mac's terms (kVK codes, ShortcutMods), so Prefs and
/// PerchCore's Shortcut are shared: ShortcutMods.command is Super, .option is Alt, .control is Ctrl, .shift is Shift.
///
/// Both live on a second X connection with its own thread (`KeyThread`): GDK's connection is the main thread's, and a
/// tap must be seen while the main thread is busy drawing. Actions hop to the main thread.
@MainActor
final class HotkeyService {
    var onChordTap: (() -> Void)?
    /// A mouse button went down or up anywhere, from raw XInput 2 events (nil if the server has none).
    var onButton: ((Bool) -> Void)?
    var hearsButtons: Bool { keys != nil }
    /// False when another app already holds the combo, so pressing it would do nothing here.
    private(set) var openCombo = true
    private static let openId: UInt32 = 4
    private var handlers: [UInt32: () -> Void] = [:]
    private var specs: [UInt32: (key: Int, mods: ShortcutMods)] = [:]
    private var armed: Set<UInt32> = []
    private let keys: KeyThread?

    init() {
        keys = KeyThread()
        if keys == nil { print("perch: no X display for global keys; shortcuts are off") }
        let me = Weak(self)
        keys?.onHotkey = { id in DispatchQueue.main.async { MainActor.assumeIsolated { me.value?.handlers[id]?() } } }
        keys?.onTap = { DispatchQueue.main.async { MainActor.assumeIsolated { me.value?.onChordTap?() } } }
        keys?.onButton = { down in DispatchQueue.main.async { MainActor.assumeIsolated { me.value?.onButton?(down) } } }
    }

    private final class Weak: @unchecked Sendable { weak var value: HotkeyService?; init(_ v: HotkeyService) { value = v } }

    /// Makes `s` the shortcut that opens Perch: a tap watches the modifiers, a combo is a grab. Both call `onChordTap`.
    func apply(_ s: Shortcut) {
        unregister(id: Self.openId)
        openCombo = true
        switch s.kind {
        case .tap: keys?.setTap(s.mods)
        case .combo:
            keys?.setTap([])
            if let code = s.keyCode { openCombo = register(keyCode: code, modifiers: s.mods, id: Self.openId) { [weak self] in self?.onChordTap?() } }
        }
    }

    /// While a new shortcut is being recorded, none of Perch's own shortcuts may fire: a grab takes its key before the
    /// recorder sees it (pressing Control+Alt+Q would quit instead of being refused).
    func pauseAll() {
        unregister(id: Self.openId)
        keys?.setTap([])
        for id in armed { keys?.ungrab(id) }
        armed = []
    }
    /// After recording: the others come back (the open shortcut is applied again by `apply`).
    func resumeAll() { for id in specs.keys where !armed.contains(id) { arm(id) } }

    /// `keyCode` is a Mac virtual key code (kVK), `modifiers` a ShortcutMods. False when another app holds that combo
    /// (or Perch does, under another id), or the key has no place on this keyboard.
    @discardableResult
    func register(keyCode: Int, modifiers: ShortcutMods, id: UInt32, action: @escaping () -> Void) -> Bool {
        handlers[id] = action
        specs[id] = (keyCode, modifiers)
        return arm(id)
    }

    func unregister(id: UInt32) {
        if armed.remove(id) != nil { keys?.ungrab(id) }
        handlers[id] = nil; specs[id] = nil
    }

    @discardableResult
    private func arm(_ id: UInt32) -> Bool {
        guard let spec = specs[id], let keys else { return false }
        if armed.remove(id) != nil { keys.ungrab(id) }
        let ok = keys.grab(id, macKeyCode: spec.key, mods: spec.mods)
        if ok { armed.insert(id) }
        else if ProcessInfo.processInfo.environment["PERCH_TRACE"] != nil { print("perch: could not grab \(spec.mods.glyphs.joined())\(spec.key) (id \(id)), another app has it") }
        return ok
    }

    /// The raw key events are selected once and need no permission; nothing to start beyond the thread `init` made.
    func startChordMonitor() {}
    /// On a Mac this follows an Accessibility grant. Here it selects the raw events again, which also recovers from a
    /// server that dropped them (it never should).
    func restartChordMonitor() { keys?.reselect() }
}

// MARK: the key thread

/// X's error handler is one for the whole process, and GDK's own connection reports through it too. Perch's handler
/// keeps errors on the key connection (a grab another client holds: BadAccess) and passes every other one on to the
/// handler that was there before, GDK's or Xlib's.
nonisolated(unsafe) private var keyConnection: OpaquePointer?
nonisolated(unsafe) private var keyError: UInt8 = 0
nonisolated(unsafe) private var previousErrorHandler: XErrorHandler?
private let chainedErrorHandler: XErrorHandler = { d, e in
    if let d, d == keyConnection, let e { keyError = e.pointee.error_code; return 0 }
    return previousErrorHandler?(d, e) ?? 0
}

/// A second X connection and the thread that owns it: grabs, raw key events, the tap. Nothing else touches the
/// connection, so Xlib needs no locking for it. Requests from the main thread run here and are waited for.
final class KeyThread: @unchecked Sendable {
    var onHotkey: (@Sendable (UInt32) -> Void)?
    var onTap: (@Sendable () -> Void)?
    /// A mouse button (1 to 3) went down (true) or up, anywhere: X has no global mouse monitor, and polling misses a tap.
    var onButton: (@Sendable (Bool) -> Void)?

    private let d: OpaquePointer
    private let root: Window
    private let wake: Int32
    private let lock = NSLock()
    private var queue: [() -> Void] = []
    private var thread: Thread?

    // Owned by the thread.
    private var xiOpcode: Int32 = -1
    private var grabs: [UInt32: Combo] = [:]
    private var byCombo: [Combo: UInt32] = [:]
    private var down: Set<UInt32> = []
    private var tap = RawKeyTap([])
    /// CapsLock, NumLock and ScrollLock: a grab must be made with each mix of them, or it fails while one is on.
    private var lockMixes: [UInt32] = [0]
    private struct Combo: Hashable { let keycode: UInt32; let state: UInt32 }
    private static let relevant: UInt32 = 0x1 | 0x4 | 0x8 | 0x40   // Shift, Control, Mod1, Mod4

    init?() {
        guard let d = XOpenDisplay(nil) else { return nil }
        self.d = d
        root = XDefaultRootWindow(d)
        wake = eventfd(0, Int32(EFD_NONBLOCK | EFD_CLOEXEC))
        keyConnection = d
        let old = XSetErrorHandler(chainedErrorHandler)
        if previousErrorHandler == nil { previousErrorHandler = old }
        XkbSetDetectableAutoRepeat(d, 1, nil)   // a held key repeats as presses only, so a repeat is told apart
        lockMixes = Self.lockMixes(d)
        selectRaw()
        let t = Thread { [unowned self] in self.loop() }
        t.name = "perch-keys"
        t.start()
        thread = t
    }

    // MARK: requests (any thread; they run on the key thread)

    func setTap(_ mods: ShortcutMods) { run { $0.tap = RawKeyTap(mods); $0.tap.reset() } }

    func grab(_ id: UInt32, macKeyCode: Int, mods: ShortcutMods) -> Bool { wait { $0.grabNow(id, macKeyCode: macKeyCode, mods: mods) } }
    func ungrab(_ id: UInt32) { run { $0.ungrabNow(id) } }
    func reselect() { run { $0.selectRaw() } }

    private func run(_ body: @escaping (KeyThread) -> Void) {
        lock.lock(); queue.append { [unowned self] in body(self) }; lock.unlock()
        var one: UInt64 = 1
        _ = write(wake, &one, 8)
    }
    private func wait<T>(_ body: @escaping (KeyThread) -> T) -> T {
        if Thread.current === thread { return body(self) }
        var out: T?
        let done = DispatchSemaphore(value: 0)
        run { out = body($0); done.signal() }
        done.wait()
        return out!
    }

    // MARK: on the thread

    private func loop() {
        let xfd = XConnectionNumber(d)
        var e = XEvent()
        while true {
            lock.lock(); let jobs = queue; queue = []; lock.unlock()
            for job in jobs { job() }
            while XPending(d) > 0 { XNextEvent(d, &e); handle(&e) }
            var fds = [pollfd(fd: xfd, events: Int16(POLLIN), revents: 0), pollfd(fd: wake, events: Int16(POLLIN), revents: 0)]
            _ = poll(&fds, 2, -1)
            if fds[1].revents != 0 { var n: UInt64 = 0; _ = read(wake, &n, 8) }
        }
    }

    private func handle(_ e: inout XEvent) {
        // X's event types by number: KeyPress 2, KeyRelease 3, MappingNotify 34, GenericEvent 35 (the app has its own KeyPress).
        switch e.type {
        case 2:
            let kc = e.xkey.keycode
            guard down.insert(kc).inserted else { return }   // a repeat
            if let id = byCombo[Combo(keycode: kc, state: e.xkey.state & Self.relevant)] { onHotkey?(id) }
        case 3:
            down.remove(e.xkey.keycode)
        case 34:
            XRefreshKeyboardMapping(&e.xmapping)
            lockMixes = Self.lockMixes(d)
        case 35:
            guard e.xcookie.extension == xiOpcode else { return }
            withUnsafeMutablePointer(to: &e.xcookie) { cookie in
                guard XGetEventData(d, cookie) != 0 else { return }
                defer { XFreeEventData(d, cookie) }
                let type = cookie.pointee.evtype
                guard (13...16).contains(type), let data = cookie.pointee.data else { return }   // XI_RawKey and XI_RawButton press, release
                let raw = data.assumingMemoryBound(to: XIRawEvent.self).pointee
                if type == 15 || type == 16 { if (1...3).contains(raw.detail) { onButton?(type == 15) }; return }   // not the wheel (4 to 7)
                if raw.flags & (1 << 16) != 0 { return }                                        // XIKeyRepeat
                let kc = UInt32(raw.detail)
                if tap.key(Int(kc), role: KeyMap.role(x11Keycode: kc, display: d), pressed: type == 13) { onTap?() }
            }
        default: break
        }
    }

    /// Raw key presses and releases from every keyboard (the master device, so a key is not seen twice).
    private func selectRaw() {
        var op: Int32 = 0, ev: Int32 = 0, err: Int32 = 0
        guard XQueryExtension(d, "XInputExtension", &op, &ev, &err) != 0 else { print("perch: no XInput extension, the modifier tap is off"); return }
        var major: Int32 = 2, minor: Int32 = 2
        guard XIQueryVersion(d, &major, &minor) == Success else { print("perch: XInput 2 missing, the modifier tap is off"); return }
        xiOpcode = op
        var bits = [UInt8](repeating: 0, count: 4)
        for t in [13, 14, 15, 16] { bits[t >> 3] |= UInt8(1 << (t & 7)) }
        bits.withUnsafeMutableBufferPointer { buf in
            var mask = XIEventMask(deviceid: 1, mask_len: Int32(buf.count), mask: buf.baseAddress)   // XIAllMasterDevices
            _ = XISelectEvents(d, root, &mask, 1)
        }
        XFlush(d)
    }

    private func grabNow(_ id: UInt32, macKeyCode: Int, mods: ShortcutMods) -> Bool {
        guard let kc = KeyMap.x11Keycode(macKeyCode: macKeyCode, display: d) else { return false }
        let combo = Combo(keycode: kc, state: LinuxKeys.x11State(mods))
        if let other = byCombo[combo], other != id { return false }   // Perch has it already, under another id
        keyError = 0
        for extra in lockMixes { XGrabKey(d, Int32(kc), combo.state | extra, root, 0, GrabModeAsync, GrabModeAsync) }
        XSync(d, 0)
        if keyError != 0 {
            for extra in lockMixes { XUngrabKey(d, Int32(kc), combo.state | extra, root) }
            XSync(d, 0); keyError = 0
            return false
        }
        grabs[id] = combo; byCombo[combo] = id
        return true
    }

    private func ungrabNow(_ id: UInt32) {
        guard let combo = grabs.removeValue(forKey: id) else { return }
        byCombo[combo] = nil
        for extra in lockMixes { XUngrabKey(d, Int32(combo.keycode), combo.state | extra, root) }
        XFlush(d)
    }

    /// Every mix of the lock modifiers: Lock (CapsLock) and whichever ModN hold Num_Lock and Scroll_Lock.
    private static func lockMixes(_ d: OpaquePointer) -> [UInt32] {
        var locks: [UInt32] = [0x2]
        if let map = XGetModifierMapping(d) {
            defer { XFreeModifiermap(map) }
            let per = Int(map.pointee.max_keypermod)
            for sym in [0xff7f, 0xff14] as [KeySym] {   // Num_Lock, Scroll_Lock
                let kc = XKeysymToKeycode(d, sym)
                guard kc != 0 else { continue }
                for mod in 3..<8 where (0..<per).contains(where: { map.pointee.modifiermap[mod * per + $0] == kc }) { locks.append(1 << UInt32(mod)) }
            }
        }
        var mixes: Set<UInt32> = [0]
        for l in locks { for m in mixes { mixes.insert(m | l) } }
        return mixes.sorted()
    }
}
