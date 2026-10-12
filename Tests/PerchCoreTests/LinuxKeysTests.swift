import Foundation
import Testing
@testable import PerchCore

@Suite struct LinuxKeysTests {
    @Test func keysKeepTheirMacCodes() {
        // X keycode = evdev + 8: A is 38, Return 36, Escape 9, the period 60, Super_L 133.
        #expect(LinuxKeys.macKeyCode(x11Keycode: 38) == 0)
        #expect(LinuxKeys.macKeyCode(x11Keycode: 36) == 36)
        #expect(LinuxKeys.macKeyCode(x11Keycode: 9) == 53)
        #expect(LinuxKeys.macKeyCode(x11Keycode: 60) == 47)
        #expect(LinuxKeys.macKeyCode(x11Keycode: 65) == 49)
        #expect(LinuxKeys.macKeyCode(x11Keycode: 133) == 55)
        #expect(LinuxKeys.macKeyCode(x11Keycode: 67) == 122)   // F1
        #expect(LinuxKeys.macKeyCode(x11Keycode: 111) == 126)  // Up
        #expect(LinuxKeys.macKeyCode(x11Keycode: 22) == 51)    // Backspace is the Mac's Delete
        #expect(LinuxKeys.macKeyCode(x11Keycode: 119) == 117)  // Delete is forward delete
        #expect(LinuxKeys.macKeyCode(x11Keycode: 248) == nil)
    }

    @Test func everyCodeGoesBothWays() {
        for x in 8..<256 { if let mac = LinuxKeys.macKeyCode(x11Keycode: x) { #expect(LinuxKeys.x11Keycode(macKeyCode: mac) == x) } }
        // The keys Perch itself registers: P, L, Q, Return, R, the period, Y, N, 1 to 3.
        for mac in [35, 37, 12, 36, 15, 47, 16, 45, 18, 19, 20] { #expect(LinuxKeys.x11Keycode(macKeyCode: mac) != nil) }
    }

    @Test func usKeysymsMatchTheKeys() {
        #expect(LinuxKeys.keysym(macKeyCode: 0) == 0x61)
        #expect(LinuxKeys.keysym(macKeyCode: 47) == 0x2e)
        #expect(LinuxKeys.keysym(macKeyCode: 36) == 0xff0d)
        #expect(LinuxKeys.keysym(macKeyCode: 111) == 0xffc9)  // F12
        #expect(LinuxKeys.macKeyCode(keysym: 0x71) == 12)     // q
    }

    @Test func modifiersAreTheMacsByName() {
        #expect(LinuxKeys.role(keysym: 0xffeb) == .modifier(.command))   // Super_L
        #expect(LinuxKeys.role(keysym: 0xffe9) == .modifier(.option))    // Alt_L
        #expect(LinuxKeys.role(keysym: 0xffe7) == .modifier(.option))    // Meta_L
        #expect(LinuxKeys.role(keysym: 0xffe4) == .modifier(.control))
        #expect(LinuxKeys.role(keysym: 0xffe2) == .modifier(.shift))
        #expect(LinuxKeys.role(keysym: 0xffe5) == .lock)
        #expect(LinuxKeys.role(keysym: 0xff7f) == .lock)
        #expect(LinuxKeys.role(keysym: 0xfe03) == .key)                  // AltGr
        #expect(LinuxKeys.role(keysym: 0x61) == .key)
    }

    @Test func modifierStatesBothWays() {
        #expect(LinuxKeys.mods(x11State: 0x40 | 0x8) == [.command, .option])
        #expect(LinuxKeys.mods(x11State: 0x10 | 0x2) == [])   // NumLock and CapsLock are not modifiers here
        #expect(LinuxKeys.x11State([.control, .option]) == 0xc)
        #expect(LinuxKeys.mods(gdkState: 1 << 26 | 0x4) == [.command, .control])
        #expect(LinuxKeys.mods(gdkState: 0x8 | 1 << 28) == [.option])
    }

    // Super_L 133, Alt_L 64, Shift_L 50, Super_R 134, the L key 46.
    private let superL = LinuxKeys.Role.modifier(.command), alt = LinuxKeys.Role.modifier(.option), shift = LinuxKeys.Role.modifier(.shift)

    @Test func aSuperAltTapOpens() {
        var t = RawKeyTap([.command, .option]); let t0 = Date()
        do { let r = t.key(133, role: superL, pressed: true, at: t0); #expect(!r) }
        do { let r = t.key(64, role: alt, pressed: true, at: t0.addingTimeInterval(0.05)); #expect(!r) }
        do { let r = t.key(64, role: alt, pressed: false, at: t0.addingTimeInterval(0.2)); #expect(!r) }
        do { let r = t.key(133, role: superL, pressed: false, at: t0.addingTimeInterval(0.25)); #expect(r) }
    }

    @Test func anotherAppsShortcutIsNoTap() {
        // Super+Alt+Shift+L: Shift and L go first, leaving Super+Alt held.
        var t = RawKeyTap([.command, .option]); let t0 = Date()
        _ = t.key(133, role: superL, pressed: true, at: t0)
        _ = t.key(64, role: alt, pressed: true, at: t0)
        _ = t.key(50, role: shift, pressed: true, at: t0)
        _ = t.key(46, role: .key, pressed: true, at: t0)
        _ = t.key(46, role: .key, pressed: false, at: t0)
        _ = t.key(50, role: shift, pressed: false, at: t0)
        _ = t.key(64, role: alt, pressed: false, at: t0)
        do { let r = t.key(133, role: superL, pressed: false, at: t0.addingTimeInterval(0.3)); #expect(!r) }
        // A key while both are held spoils it too, and so does holding too long.
        _ = t.key(133, role: superL, pressed: true, at: t0); _ = t.key(64, role: alt, pressed: true, at: t0)
        _ = t.key(46, role: .key, pressed: true, at: t0)
        _ = t.key(64, role: alt, pressed: false, at: t0)
        do { let r = t.key(133, role: superL, pressed: false, at: t0); #expect(!r) }
        _ = t.key(133, role: superL, pressed: true, at: t0); _ = t.key(64, role: alt, pressed: true, at: t0)
        _ = t.key(64, role: alt, pressed: false, at: t0.addingTimeInterval(0.5))
        do { let r = t.key(133, role: superL, pressed: false, at: t0.addingTimeInterval(0.7)); #expect(!r) }
    }

    @Test func bothSuperKeysAreOneModifier() {
        // Letting go of the left one while the right is still down keeps Super held.
        var t = RawKeyTap([.command, .option]); let t0 = Date()
        _ = t.key(133, role: superL, pressed: true, at: t0)
        _ = t.key(134, role: superL, pressed: true, at: t0)
        _ = t.key(133, role: superL, pressed: false, at: t0)
        #expect(t.mods == [.command])
        _ = t.key(64, role: alt, pressed: true, at: t0)
        _ = t.key(64, role: alt, pressed: false, at: t0)
        do { let r = t.key(134, role: superL, pressed: false, at: t0.addingTimeInterval(0.1)); #expect(r) }
    }

    @Test func lockKeysChangeNothing() {
        var t = RawKeyTap([.command, .option]); let t0 = Date()
        _ = t.key(133, role: superL, pressed: true, at: t0); _ = t.key(64, role: alt, pressed: true, at: t0)
        _ = t.key(77, role: .lock, pressed: true, at: t0); _ = t.key(77, role: .lock, pressed: false, at: t0)
        _ = t.key(64, role: alt, pressed: false, at: t0)
        do { let r = t.key(133, role: superL, pressed: false, at: t0.addingTimeInterval(0.1)); #expect(r) }
    }
}
