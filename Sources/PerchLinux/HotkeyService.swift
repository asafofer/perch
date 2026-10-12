import CPerchLinux
import Foundation
import PerchCore

// OWNER: the input-and-desktop agent. STUB.
// Global keys on X11 (XGrabKey on the root window) and the modifier tap that opens Perch (XInput2 raw key events).
// Key codes and modifiers stay in the Mac's terms (kVK codes, ShortcutMods), so Prefs and PerchCore's Shortcut are
// shared: ShortcutMods.command is Super, .option is Alt, .control is Ctrl, .shift is Shift.
@MainActor
final class HotkeyService {
    var onChordTap: (() -> Void)?
    private(set) var openCombo = true
    func apply(_ s: Shortcut) {}
    func pauseAll() {}
    func resumeAll() {}
    /// `keyCode` is a Mac virtual key code (kVK), `modifiers` a ShortcutMods raw value.
    @discardableResult func register(keyCode: Int, modifiers: ShortcutMods, id: UInt32, action: @escaping () -> Void) -> Bool { false }
    func unregister(id: UInt32) {}
    func startChordMonitor() {}
    func restartChordMonitor() {}
}
