import CPerchLinux
import Foundation
import PerchCore

/// One key press, as the Mac's NSEvent gives it to the recorder and the list: the Mac key code for the key's place,
/// what it types, and the modifiers held.
struct KeyPress {
    /// Mac virtual key code (kVK), or -1 for a key the Mac has none for (a media key).
    let keyCode: Int
    /// The key's character with no modifiers, letters lowercase (charactersIgnoringModifiers, as the recorder wants it).
    let typed: String?
    /// What the key types with Shift applied, for typing into the list's filter. Nil for keys that type nothing.
    let characters: String?
    let mods: ShortcutMods
}

/// X keys in the Mac's terms (see LinuxKeys in PerchCore): kVK codes and ShortcutMods, Super as Command, Alt as Option.
enum KeyMap {
    /// The shortcut that opens Perch here: a tap of Super and Alt, the Mac's Command+Option. Xfce binds nothing to Super
    /// alone or to Super+Alt, and a tap never reaches another app's Super shortcut (it sends no key).
    static let defaultShortcut = Shortcut.standard

    /// A GTK key event (GDK keyval, hardware X keycode, GdkModifierType) in the Mac's terms. Main thread.
    static func press(keyval: UInt32, keycode: UInt32, state: UInt32) -> KeyPress {
        let d = X11.display
        let code = d.flatMap { macKeyCode(x11Keycode: keycode, display: $0) } ?? LinuxKeys.macKeyCode(x11Keycode: Int(keycode)) ?? -1
        // What the key types on the current layout with nothing held: level 0 of the active group.
        var typed: String?
        if let d {
            var st = XkbStateRec()
            XkbGetState(d, UInt32(XkbUseCoreKbd), &st)
            let base = XkbKeycodeToKeysym(d, KeyCode(truncatingIfNeeded: keycode), Int32(st.group), 0)
            typed = text(UInt32(truncatingIfNeeded: base))?.lowercased()
        }
        return KeyPress(keyCode: code, typed: typed ?? text(keyval)?.lowercased(), characters: text(keyval), mods: mods(state: state))
    }

    /// GdkModifierType to ShortcutMods.
    static func mods(state: UInt32) -> ShortcutMods { LinuxKeys.mods(gdkState: state) }

    /// For a modifier key going down or up: the modifiers held after it, which is what the Mac's flagsChanged carries and
    /// what the recorder and the shortcut step's big keys want (GTK gives the state from before the event). Nil for any
    /// other key. Letting go of one Shift while the other is still down reads as no Shift.
    static func flags(keyval: UInt32, state: UInt32, pressed: Bool) -> ShortcutMods? {
        guard case .modifier(let m) = LinuxKeys.role(keysym: keyval) else { return nil }
        var after = mods(state: state)
        if pressed { after.insert(m) } else { after.remove(m) }
        return after
    }

    /// The character a keysym types, nil for one that types nothing (Return, arrows, a modifier).
    private static func text(_ keysym: UInt32) -> String? {
        let u = gdk_keyval_to_unicode(keysym)
        guard u >= 0x20, u != 0x7f, let s = Unicode.Scalar(u) else { return nil }
        return String(Character(s))
    }

    // MARK: keycodes on a given connection (also used off the main thread, with the key thread's own connection)

    /// Whether this server numbers keys as evdev does (keycode = evdev + 8): Escape is 9 and Return 36. Every current X
    /// server does; otherwise keys are found by what they type on a US layout.
    static func evdev(_ d: OpaquePointer) -> Bool { XKeysymToKeycode(d, 0xff1b) == 9 && XKeysymToKeycode(d, 0xff0d) == 36 }

    static func x11Keycode(macKeyCode: Int, display d: OpaquePointer) -> UInt32? {
        if evdev(d) { return LinuxKeys.x11Keycode(macKeyCode: macKeyCode).map { UInt32($0) } }
        guard let sym = LinuxKeys.keysym(macKeyCode: macKeyCode) else { return nil }
        let k = XKeysymToKeycode(d, KeySym(sym))
        return k == 0 ? nil : UInt32(k)
    }

    static func macKeyCode(x11Keycode: UInt32, display d: OpaquePointer) -> Int? {
        if evdev(d) { return LinuxKeys.macKeyCode(x11Keycode: Int(x11Keycode)) }
        let sym = XkbKeycodeToKeysym(d, KeyCode(truncatingIfNeeded: x11Keycode), 0, 0)
        return LinuxKeys.macKeyCode(keysym: UInt32(truncatingIfNeeded: sym))
    }

    /// What a keycode is to the tap: a modifier, a lock key or any other key, by its keysym in the first group.
    static func role(x11Keycode: UInt32, display d: OpaquePointer) -> LinuxKeys.Role {
        LinuxKeys.role(keysym: UInt32(truncatingIfNeeded: XkbKeycodeToKeysym(d, KeyCode(truncatingIfNeeded: x11Keycode), 0, 0)))
    }
}
