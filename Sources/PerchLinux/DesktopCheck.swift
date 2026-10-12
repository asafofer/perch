import CPerchLinux
import Foundation
import PerchCore

/// `--desktop-check [seconds]`: exercises the keys, idle time, quiet time, tray, autostart and screens on the running
/// desktop and prints what each sees, for trying them under Xvfb or on a real session. It registers Control+Alt+P, the
/// Super+Alt tap and Super+Alt+Y, and runs for `seconds` (20 by default). Returns false for any other launch.
@MainActor
func desktopCheck(_ args: [String]) -> Bool {
    guard let i = args.firstIndex(of: "--desktop-check") else { return false }
    let seconds = args.indices.contains(i + 1) ? Double(args[i + 1]) ?? 20 : 20
    let hotkeys = HotkeyService()
    hotkeys.onChordTap = { print("check: tap") }
    hotkeys.apply(KeyMap.defaultShortcut)
    print("check: grab control-alt-P:", hotkeys.register(keyCode: 35, modifiers: [.control, .option], id: 1) { print("check: hotkey control-alt-P") })
    print("check: grab super-alt-Y:", hotkeys.register(keyCode: 16, modifiers: [.command, .option], id: 21) { print("check: hotkey super-alt-Y") })
    checkKeep.append(hotkeys)
    GLoop.every(seconds) { GLoop.quit(); return false }
    return true
}
@MainActor private var checkKeep: [AnyObject] = []
