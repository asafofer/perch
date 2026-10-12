import CPerchLinux
import Foundation
import PerchCore

/// `--desktop-check [seconds]`: exercises the keys, idle time, quiet time, tray, autostart and screens on the running
/// desktop and prints what each sees, for trying them under Xvfb or on a real session. It registers Control+Alt+P, the
/// Super+Alt tap and Super+Alt+Y, puts up the tray icon, reports idle and quiet every two seconds, and quits after
/// `seconds` (20 by default). Returns false for any other launch.
@MainActor
func desktopCheck(_ args: [String]) -> Bool {
    guard let i = args.firstIndex(of: "--desktop-check") else { return false }
    let seconds = args.indices.contains(i + 1) ? Double(args[i + 1]) ?? 20 : 20
    for s in Screen.screens {
        print("check: screen \(s.displayID) \(s.localizedName) frame \(s.frame) visible \(s.visibleFrame) menu bar \(s.menuBarHeight)")
    }
    print("check: main screen \(Screen.main?.displayID ?? "none")")
    print("check: autostart \(Autostart.isOn ? "on" : "off"), would run \(Autostart.quoted(Autostart.executable))")

    let hotkeys = HotkeyService()
    hotkeys.onChordTap = { print("check: tap") }
    hotkeys.apply(KeyMap.defaultShortcut)
    print("check: grab control-alt-P:", hotkeys.register(keyCode: 35, modifiers: [.control, .option], id: 1) { print("check: hotkey control-alt-P") })
    print("check: grab super-alt-Y:", hotkeys.register(keyCode: 16, modifiers: [.command, .option], id: 21) { print("check: hotkey super-alt-Y") })

    let tray = Tray(items: [Tray.Item(title: "Test build: check", action: {}, enabled: false), nil,
                            Tray.Item(title: "Where was I", action: { print("check: menu Where was I") }),
                            Tray.Item(title: "All sessions", action: { print("check: menu All sessions") }), nil,
                            Tray.Item(title: "Quit Perch", action: { print("check: menu Quit"); GLoop.quit() })])
    if let png = ProcessInfo.processInfo.environment["PERCH_CHECK_ICON"].flatMap({ FileManager.default.contents(atPath: $0) }) {
        tray.setIcon(png: png)
        print("check: icon set from PNG")
    }
    let monitor = ActivityMonitor(threshold: Double(ProcessInfo.processInfo.environment["PERCH_CHECK_IDLE"] ?? "") ?? 6)
    monitor.onReturn = { since in print("check: back, away since \(since.map { String(format: "%.0f s ago", Date().timeIntervalSince($0)) } ?? "?")") }
    checkKeep += [hotkeys, tray, monitor]
    var last = ""
    GLoop.every(2) {
        let line = "idle \(Int(ActivityMonitor.idleSeconds())) s, locked \(ActivityMonitor.screenLocked), quiet: \(Quiet.reason() ?? "no"), launcher: \(Quiet.launcherOpen() ?? "none")"
        if line != last { print("check: \(line)"); last = line }
        return true
    }
    GLoop.every(seconds) { GLoop.quit(); return false }
    return true
}
@MainActor private var checkKeep: [AnyObject] = []
