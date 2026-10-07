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
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), args.indices.contains(i + 1) {
            let dir = args[i + 1]
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { c.snapshot(to: dir + "/idle.png") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { c.comeBack() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.4) { c.snapshot(to: dir + "/open.png") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.8) { c.send(.openSwitcher) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.2) { c.snapshot(to: dir + "/switcher.png") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.6) { c.confirm() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 7.4) { c.snapshot(to: dir + "/restoring.png") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8.5) { NSApp.terminate(nil) }
        }
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
