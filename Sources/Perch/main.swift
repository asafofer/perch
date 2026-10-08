import AppKit
import Carbon.HIToolbox
import PerchCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchController?
    private var activity: ActivityMonitor?
    private var statusItem: NSStatusItem?
    private let hotkeys = HotkeyService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if args.contains("--ai-check") {
            if let why = AppleRecapEngine.unavailableReason { print("On-device model unavailable: \(why)"); exit(1) }
            let real = RealSessionProvider()
            let projects = real.parkedProjects()
            Task {
                for p in projects {
                    guard let input = real.inputs[p.id] else { continue }
                    let t0 = Date()
                    let r = await AppleRecapEngine.recap(digest: input.digest, git: input.git, name: p.name)
                    let merged = r.map { RecapMerge.apply($0, to: p, grounding: input.digest) }
                    print("== \(p.name)  (\(String(format: "%.1f", Date().timeIntervalSince(t0)))s)")
                    print("  plain : \(p.headline) | \(p.context) | \(p.next)")
                    print("  model : \(merged.map { "\($0.headline) | \($0.context) | \($0.next)" } ?? "failed")")
                }
                exit(0)
            }
            return
        }
        if args.contains("--dump") {
            for p in RealSessionProvider().parkedProjects() {
                print("\(p.name) | \(p.branch ?? "-") | left \(p.at) (\(p.away) ago) | \(p.status.kind): \(p.status.text)")
                print("   headline: \(p.headline)\n   context:  \(p.context)\n   next:     \(p.next)\n   opens:    \(p.desktopSessionId.map { "claude://code/continue?session=" + $0 } ?? "Terminal: claude --resume \(p.sessionId ?? "?")")")
            }
            exit(0)
        }
        // Demos and snapshots always use sample data, so they never open Terminal.
        let sample = args.contains("--fake") || ((args.contains("--demo") || args.contains("--snapshot")) && !args.contains("--real"))
        let provider: SessionProviding = sample ? FakeSessionProvider() : RealSessionProvider()
        let c = NotchController(provider: provider)
        controller = c

        hotkeys.register(keyCode: kVK_ANSI_P, modifiers: controlKey | optionKey, id: 1) { c.comeBack() }
        hotkeys.register(keyCode: kVK_ANSI_L, modifiers: controlKey | optionKey, id: 2) { c.toggleSwitcher() }
        hotkeys.register(keyCode: kVK_ANSI_Q, modifiers: controlKey | optionKey, id: 3) { NSApp.terminate(nil) }
        hotkeys.onChordTap = { c.chordTap() }
        hotkeys.startChordMonitor()

        if !sample {
            var seconds: TimeInterval = 20 * 60
            if let i = args.firstIndex(of: "--idle"), args.indices.contains(i + 1), let v = TimeInterval(args[i + 1]) { seconds = v }
            let monitor = ActivityMonitor(threshold: seconds)
            monitor.onReturn = { c.comeBack(proactive: true) }
            activity = monitor
            installStatusItem()
            // First run: offer the guided setup once, a moment after launch.
            let key = "setupOffered"
            if !UserDefaults.standard.bool(forKey: key), AppleRecapEngine.setupState != "ready" {
                UserDefaults.standard.set(true, forKey: key)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { c.showSetup() }
            }
        }

        if let i = args.firstIndex(of: "--snapshot"), args.indices.contains(i + 1) {
            let dir = args[i + 1]
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { c.snapshot(to: dir + "/idle.png") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { c.comeBack() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.2) { c.snapshot(to: dir + "/open.png") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.6) { c.send(.openSwitcher) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.2) { c.snapshot(to: dir + "/switcher.png") }
            if !args.contains("--real") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 6.6) { c.confirm() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 8.6) { c.snapshot(to: dir + "/restoring.png") }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.4) { c.send(.dismiss) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.8) { c.showSetup() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 12.4) { c.snapshot(to: dir + "/setup.png") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 13.4) { NSApp.terminate(nil) }
        }
        if args.contains("--simulate") {
            // "I was away, I'm back": asleep for a few seconds, then you return and the card stays open.
            c.holdOpen = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { c.comeBack() }
        }
        if args.contains("--setup") { DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { c.showSetup() } }
        if args.contains("--show") { DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { c.comeBack() } }
        if args.contains("--demo") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { c.comeBack() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { c.confirm() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 12.0) { NSApp.terminate(nil) }
        }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { r in
            let p = NSBezierPath()
            p.move(to: NSPoint(x: 3, y: 3)); p.line(to: NSPoint(x: 3, y: 9))
            p.appendArc(withCenter: NSPoint(x: 9, y: 9), radius: 6, startAngle: 180, endAngle: 0, clockwise: true)
            p.line(to: NSPoint(x: 15, y: 3)); p.close()
            NSColor.black.setFill(); p.fill(); return true
        }
        image.isTemplate = true
        item.button?.image = image
        let menu = NSMenu()
        menu.addItem(withTitle: "Welcome back now", action: #selector(showWelcome), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Parked projects", action: #selector(showSwitcher), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let ai = AppleRecapEngine.unavailableReason == nil
            ? NSMenuItem(title: "Summaries: on-device", action: nil, keyEquivalent: "")
            : NSMenuItem(title: "Set up better summaries…", action: #selector(showSetup), keyEquivalent: "")
        ai.target = self; ai.isEnabled = AppleRecapEngine.unavailableReason != nil
        menu.addItem(ai)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Perch", action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu
        statusItem = item
    }
    @objc private func showWelcome() { controller?.comeBack() }
    @objc private func showSwitcher() { controller?.toggleSwitcher() }
    @objc private func showSetup() { controller?.showSetup() }
    @objc private func openSystemSettings() { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app")) }
    @objc private func quit() { NSApp.terminate(nil) }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
