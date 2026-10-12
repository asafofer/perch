import Foundation

/// Linux keyboards in the Mac's terms, so Prefs and `Shortcut` are shared: a key is the Mac's virtual key code for the
/// same place on the keyboard (kVK_ANSI_A is the key right of Caps Lock, whatever it types), and Super is Command, Alt
/// is Option. X keycodes are evdev's plus 8 on every current X server (Xorg with libinput or evdev, Xvfb, XWayland).
/// Pure tables and rules; the X11 calls live in the Linux app.
public enum LinuxKeys {
    /// (evdev code, Mac virtual key code, the X keysym a US layout gives it).
    private static let table: [(evdev: Int, mac: Int, keysym: UInt32)] = {
        var t: [(Int, Int, UInt32)] = []
        // Letters.
        let letters: [(Character, Int, Int)] = [("a", 30, 0), ("b", 48, 11), ("c", 46, 8), ("d", 32, 2), ("e", 18, 14), ("f", 33, 3), ("g", 34, 5),
            ("h", 35, 4), ("i", 23, 34), ("j", 36, 38), ("k", 37, 40), ("l", 38, 37), ("m", 50, 46), ("n", 49, 45), ("o", 24, 31), ("p", 25, 35),
            ("q", 16, 12), ("r", 19, 15), ("s", 31, 1), ("t", 20, 17), ("u", 22, 32), ("v", 47, 9), ("w", 17, 13), ("x", 45, 7), ("y", 21, 16), ("z", 44, 6)]
        for (c, e, m) in letters { t.append((e, m, UInt32(c.asciiValue!))) }
        // The digit row.
        let digits: [(Character, Int, Int)] = [("1", 2, 18), ("2", 3, 19), ("3", 4, 20), ("4", 5, 21), ("5", 6, 23), ("6", 7, 22), ("7", 8, 26),
                                                ("8", 9, 28), ("9", 10, 25), ("0", 11, 29)]
        for (c, e, m) in digits { t.append((e, m, UInt32(c.asciiValue!))) }
        t += [
            (12, 27, 0x2d), (13, 24, 0x3d), (26, 33, 0x5b), (27, 30, 0x5d), (39, 41, 0x3b), (40, 39, 0x27), (41, 50, 0x60), (43, 42, 0x5c),
            (51, 43, 0x2c), (52, 47, 0x2e), (53, 44, 0x2f), (86, 10, 0x3c),          // - = [ ] ; ' ` \ , . / and the ISO key by Shift
            (57, 49, 0x20), (28, 36, 0xff0d), (1, 53, 0xff1b), (15, 48, 0xff09),      // Space, Return, Escape, Tab
            (14, 51, 0xff08), (111, 117, 0xffff), (110, 114, 0xff63),                // Backspace (the Mac's Delete), Delete, Insert (Help)
            (102, 115, 0xff50), (107, 119, 0xff57), (104, 116, 0xff55), (109, 121, 0xff56),
            (105, 123, 0xff51), (106, 124, 0xff53), (108, 125, 0xff54), (103, 126, 0xff52),
            (96, 76, 0xff8d),                                                        // keypad Enter
            (82, 82, 0xffb0), (79, 83, 0xffb1), (80, 84, 0xffb2), (81, 85, 0xffb3), (75, 86, 0xffb4), (76, 87, 0xffb5), (77, 88, 0xffb6),
            (71, 89, 0xffb7), (72, 91, 0xffb8), (73, 92, 0xffb9), (83, 65, 0xffae), (55, 67, 0xffaa), (78, 69, 0xffab), (74, 78, 0xffad),
            (98, 75, 0xffaf), (117, 81, 0xffbd),
            // Modifiers: Control, Shift, Alt (Option), Super (Command), left then right; Caps Lock.
            (29, 59, 0xffe3), (97, 62, 0xffe4), (42, 56, 0xffe1), (54, 60, 0xffe2), (56, 58, 0xffe9), (100, 61, 0xffea),
            (125, 55, 0xffeb), (126, 54, 0xffec), (58, 57, 0xffe5),
        ]
        // F1 to F20.
        let fkeys = [(59, 122), (60, 120), (61, 99), (62, 118), (63, 96), (64, 97), (65, 98), (66, 100), (67, 101), (68, 109), (87, 103), (88, 111),
                     (183, 105), (184, 107), (185, 113), (186, 106), (187, 64), (188, 79), (189, 80), (190, 90)]
        for (i, (e, m)) in fkeys.enumerated() { t.append((e, m, 0xffbe + UInt32(i))) }
        return t.map { (evdev: $0.0, mac: $0.1, keysym: $0.2) }
    }()
    private static let byX = Dictionary(uniqueKeysWithValues: table.map { ($0.evdev + 8, $0.mac) })
    private static let byMac = Dictionary(uniqueKeysWithValues: table.map { ($0.mac, $0.evdev + 8) })
    private static let symByMac = Dictionary(uniqueKeysWithValues: table.map { ($0.mac, $0.keysym) })
    private static let macBySym = Dictionary(table.map { ($0.keysym, $0.mac) }, uniquingKeysWith: { a, _ in a })

    /// The Mac key code for an X keycode (its place on the keyboard), or nil for a key the Mac has no code for.
    public static func macKeyCode(x11Keycode: Int) -> Int? { byX[x11Keycode] }
    /// The X keycode for a Mac key code, on a server with evdev keycodes.
    public static func x11Keycode(macKeyCode: Int) -> Int? { byMac[macKeyCode] }
    /// What that key types on a US layout: for a server whose keycodes are not evdev's, the keycode is looked up by this.
    public static func keysym(macKeyCode: Int) -> UInt32? { symByMac[macKeyCode] }
    /// The Mac key code for a US-layout keysym (lowercase letters).
    public static func macKeyCode(keysym: UInt32) -> Int? { macBySym[keysym] }

    /// What a key is to the modifier tap: a modifier Perch knows, a lock key (it changes nothing), or any other key.
    public enum Role: Equatable, Sendable { case modifier(ShortcutMods), lock, key }

    /// By what the key's keysym is, so a remapped key counts as what it does (Caps Lock made Control is Control).
    /// Meta is Alt's other name; Hyper sits with Super. AltGr (ISO_Level3_Shift) is a key: it is no modifier a Mac has.
    public static func role(keysym: UInt32) -> Role {
        switch keysym {
        case 0xffe1, 0xffe2: return .modifier(.shift)
        case 0xffe3, 0xffe4: return .modifier(.control)
        case 0xffe7, 0xffe8, 0xffe9, 0xffea: return .modifier(.option)
        case 0xffeb, 0xffec, 0xffed, 0xffee: return .modifier(.command)
        case 0xffe5, 0xffe6, 0xff7f, 0xff14: return .lock   // Caps_Lock, Shift_Lock, Num_Lock, Scroll_Lock
        default: return .key
        }
    }

    /// X's modifier state (an event's `state`): Shift 1, Control 4, Mod1 (Alt) 8, Mod4 (Super) 0x40.
    public static func mods(x11State: UInt) -> ShortcutMods {
        var m: ShortcutMods = []
        if x11State & 0x1 != 0 { m.insert(.shift) }
        if x11State & 0x4 != 0 { m.insert(.control) }
        if x11State & 0x8 != 0 { m.insert(.option) }
        if x11State & 0x40 != 0 { m.insert(.command) }
        return m
    }
    /// The X modifier bits for ShortcutMods, for a key grab.
    public static func x11State(_ m: ShortcutMods) -> UInt32 {
        (m.contains(.shift) ? 0x1 : 0) | (m.contains(.control) ? 0x4 : 0) | (m.contains(.option) ? 0x8 : 0) | (m.contains(.command) ? 0x40 : 0)
    }
    /// GTK 4's GdkModifierType: Shift 1, Control 4, Alt 8, Super 1 << 26, Hyper 1 << 27. Meta (1 << 28) is left out: on a
    /// standard keymap it comes with Alt. Mod4's own bit counts as Super too, in case a raw X state is passed.
    public static func mods(gdkState: UInt32) -> ShortcutMods {
        var m: ShortcutMods = []
        if gdkState & 0x1 != 0 { m.insert(.shift) }
        if gdkState & 0x4 != 0 { m.insert(.control) }
        if gdkState & 0x8 != 0 { m.insert(.option) }
        if gdkState & (1 << 26 | 1 << 27 | 0x40) != 0 { m.insert(.command) }
        return m
    }
}

/// `ModifierTap` fed from raw key presses and releases, as X's input extension reports them for the whole screen (even
/// keys another app has grabbed). X sends no "modifiers changed" event and no count of key presses, so this keeps both:
/// which modifier keys are down (left and right apart), and how many other keys went down.
public struct RawKeyTap: Sendable {
    public var tap: ModifierTap
    private var held: [Int: ShortcutMods] = [:]
    private var keyDowns = 0
    public init(_ mods: ShortcutMods) { tap = ModifierTap(mods) }

    /// The modifiers held now.
    public var mods: ShortcutMods { held.values.reduce(into: ShortcutMods()) { $0.formUnion($1) } }

    /// A key went down or up. True when that completed a tap of `tap.mods`.
    public mutating func key(_ keycode: Int, role: LinuxKeys.Role, pressed: Bool, at time: Date = Date()) -> Bool {
        switch role {
        case .lock: return false
        case .key:
            if pressed { keyDowns += 1; tap.keyDown() }
            return false
        case .modifier(let m):
            if pressed { held[keycode] = m } else { held[keycode] = nil }
            return tap.flagsChanged(mods, keyDowns: keyDowns, at: time)
        }
    }

    /// Forget the press under way (the shortcut changed, or recording began).
    public mutating func reset() { tap.reset() }
}
