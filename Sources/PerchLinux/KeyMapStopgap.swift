import CPerchLinux
import Foundation
import PerchCore

// TEMPORARY: replaced by the input agent's KeyMap.swift at merge (same API). Only the keys the card handles.
struct KeyPress { let keyCode: Int; let typed: String?; let characters: String?; let mods: ShortcutMods }

enum KeyMap {
    static func press(keyval: UInt32, keycode: UInt32, state: UInt32) -> KeyPress {
        let named: [UInt32: Int] = [0xff0d: 36, 0xff8d: 76, 0xff1b: 53, 0xff09: 48, 0xff08: 51, 0xff51: 123, 0xff53: 124, 0xff54: 125, 0xff52: 126, 0x20: 49]
        let lower = gdk_keyval_to_lower(keyval)
        let ch = gdk_keyval_to_unicode(lower)
        let typed = ch > 0 ? String(UnicodeScalar(ch).map(Character.init) ?? " ") : nil
        let full = gdk_keyval_to_unicode(keyval)
        let chars = full > 0 ? String(UnicodeScalar(full).map(Character.init) ?? " ") : nil
        let letters: [Character: Int] = ["a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
                                         "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29, "o": 31, "u": 32,
                                         "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46, ",": 43, ".": 47]
        let code = named[keyval] ?? typed.flatMap { $0.first }.flatMap { letters[$0] } ?? -1
        return KeyPress(keyCode: code, typed: typed, characters: chars, mods: mods(state: state))
    }
    static func mods(state: UInt32) -> ShortcutMods {
        var m: ShortcutMods = []
        if state & GDK_SUPER_MASK.rawValue != 0 { m.insert(.command) }
        if state & GDK_ALT_MASK.rawValue != 0 { m.insert(.option) }
        if state & GDK_CONTROL_MASK.rawValue != 0 { m.insert(.control) }
        if state & GDK_SHIFT_MASK.rawValue != 0 { m.insert(.shift) }
        return m
    }
}
