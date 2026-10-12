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
    if ProcessInfo.processInfo.environment["PERCH_CHECK_AUTOSTART"] != nil {
        let was = Autostart.isOn
        Autostart.set(true); print("check: autostart after set(true): \(Autostart.isOn)")
        Autostart.set(false); print("check: autostart after set(false): \(Autostart.isOn)")
        Autostart.set(was)   // as it was found
    }

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
    if ProcessInfo.processInfo.environment["PERCH_CHECK_KEYS"] != nil { keyWindow() }
    var last = ""
    GLoop.every(2) {
        let line = "idle \(Int(ActivityMonitor.idleSeconds())) s, locked \(ActivityMonitor.screenLocked), quiet: \(Quiet.reason() ?? "no"), launcher: \(Quiet.launcherOpen() ?? "none")"
        if line != last { print("check: \(line)"); last = line }
        if ProcessInfo.processInfo.environment["PERCH_CHECK_TIMING"] != nil {
            func ms(_ f: () -> Any?) -> String { let t = Date(); _ = f(); return String(format: "%.0f ms", Date().timeIntervalSince(t) * 1000) }
            print("check: mic \(ms { Quiet.appUsingMic() }), camera \(ms { Quiet.cameraInUse() }), presenting \(ms { Quiet.presenting() }), launcher \(ms { Quiet.launcherOpen() }), idle \(ms { ActivityMonitor.idleSeconds() })")
        }
        return true
    }
    GLoop.every(seconds) { GLoop.quit(); return false }
    return true
}
@MainActor private var checkKeep: [AnyObject] = []

/// A plain GTK window that prints each key as KeyMap reads it: for checking the controller's key path.
@MainActor private func keyWindow() {
    let window = gtk_window_new()!
    gtk_window_set_title(UnsafeMutableRawPointer(window).assumingMemoryBound(to: GtkWindow.self), "perch-keys")
    gtk_window_set_default_size(UnsafeMutableRawPointer(window).assumingMemoryBound(to: GtkWindow.self), 300, 200)
    let keys = gtk_event_controller_key_new()
    let pressed: @convention(c) (OpaquePointer?, UInt32, UInt32, UInt32, UnsafeMutableRawPointer?) -> Int32 = { _, keyval, keycode, state, _ in
        MainActor.assumeIsolated {
            let k = KeyMap.press(keyval: keyval, keycode: keycode, state: state)
            let flags = KeyMap.flags(keyval: keyval, state: state, pressed: true)
            print("check: key down kVK \(k.keyCode) typed \(k.typed ?? "nil") chars \(k.characters ?? "nil") mods \(k.mods.glyphs.joined())\(flags.map { " flags after \($0.glyphs.joined())" } ?? "")")
        }
        return 0
    }
    let released: @convention(c) (OpaquePointer?, UInt32, UInt32, UInt32, UnsafeMutableRawPointer?) -> Void = { _, keyval, _, state, _ in
        MainActor.assumeIsolated { if let f = KeyMap.flags(keyval: keyval, state: state, pressed: false) { print("check: modifier up, flags after \(f.glyphs.joined())") } }
    }
    _ = perch_connect(UnsafeMutableRawPointer(keys), "key-pressed", unsafeBitCast(pressed, to: GCallback.self), nil)
    _ = perch_connect(UnsafeMutableRawPointer(keys), "key-released", unsafeBitCast(released, to: GCallback.self), nil)
    gtk_widget_add_controller(window, keys)
    gtk_widget_show(window)
}
