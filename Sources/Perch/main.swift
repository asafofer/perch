import AppKit
import Carbon.HIToolbox
import PerchCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchController?
    private let hotkeys = HotkeyService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let c = NotchController(provider: FakeSessionProvider())
        controller = c
        // Command+Option+Space: switcher (works without any permission).
        hotkeys.register(keyCode: kVK_Space, modifiers: cmdKey | optionKey, id: 1) { c.toggleSwitcher() }
        // Control+Option+Space: simulate "welcome back" (milestone 1 testing).
        hotkeys.register(keyCode: kVK_Space, modifiers: controlKey | optionKey, id: 2) { c.comeBack() }
        // Control+Option+Q: quit (the app has no menu bar item).
        hotkeys.register(keyCode: kVK_ANSI_Q, modifiers: controlKey | optionKey, id: 3) { NSApp.terminate(nil) }
        hotkeys.onChordTap = { c.toggleSwitcher() }
        hotkeys.startChordMonitor()
        if CommandLine.arguments.contains("--demo") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { c.comeBack() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { c.confirm() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 12.0) { NSApp.terminate(nil) }
        }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
