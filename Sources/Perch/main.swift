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
        if let flag = args.first(where: { $0 == "--install-hooks" || $0 == "--uninstall-hooks" }) {
            for agent in ["claude", "codex"] {
                do { if flag == "--install-hooks" { try HookInstaller.install(agent) } else { try HookInstaller.uninstall(agent) } ; print("\(agent): \(HookInstaller.isInstalled(agent) ? "on" : "off")") }
                catch { print("\(agent): \(error.localizedDescription)") }
            }
            exit(0)
        }
        // The design page draws stand-in icons; this writes this Mac's real ones next to it (git ignores the file).
        if let i = args.firstIndex(of: "--design-icons") {
            let out = URL(fileURLWithPath: i + 1 < args.count ? args[i + 1] : "ui/icons.local.json")
            do { try JSONSerialization.data(withJSONObject: AppIcons.all(), options: [.sortedKeys]).write(to: out); print("wrote \(out.path)") }
            catch { print("could not write \(out.path): \(error)") }
            exit(0)
        }
        if args.contains("--dump") {
            for p in RealSessionProvider().parkedProjects() {
                let opens = p.terminal ? "\(p.via ?? Terminals.preferred): \(p.app == "codex" ? "codex resume" : "claude --resume") \(p.sessionId ?? "?")"
                    : p.app == "codex" ? "codex://threads/\(p.sessionId ?? "?")" : "claude://code/continue?session=\(p.desktopSessionId ?? "?")"
                print("\(p.name) | \(p.branch ?? "-") | left \(p.at) (\(p.away) ago) | \(p.status.kind): \(p.status.text)")
                print("   headline: \(p.headline)\n   context:  \(p.context)\n   next:     \(p.next)\n   opens:    \(opens)")
            }
            for hit in LiveSessions.all() { print("live in a terminal: \(hit.agent) pid \(hit.pid) in \(hit.cwd) on \(hit.tty), \(hit.app ?? "no app")") }
            print("speak up on its own now: \(Quiet.reason().map { "no, \($0)" } ?? "yes")")
            exit(0)
        }
        // Demos and snapshots always use sample data, so they never open Terminal.
        let sample = args.contains("--fake") || ((args.contains("--demo") || args.contains("--snapshot") || args.contains("--record")) && !args.contains("--real"))
        let provider: SessionProviding = sample ? FakeSessionProvider() : RealSessionProvider()
        let c = NotchController(provider: provider)
        controller = c

        hotkeys.register(keyCode: kVK_ANSI_P, modifiers: controlKey | optionKey, id: 1) { c.comeBack() }
        hotkeys.register(keyCode: kVK_ANSI_L, modifiers: controlKey | optionKey, id: 2) { c.toggleSwitcher() }
        hotkeys.register(keyCode: kVK_ANSI_Q, modifiers: controlKey | optionKey, id: 3) { NSApp.terminate(nil) }
        // While the notch says an answer or a request arrived, its buttons answer to Command+Option and a key. Only then.
        let activityCodes: [String: Int] = ["pick": kVK_Return, "open": kVK_Return, "reply": kVK_ANSI_R, "gone": kVK_ANSI_Period,
                                            "allow": kVK_ANSI_Y, "deny": kVK_ANSI_N, "pick1": kVK_ANSI_1, "pick2": kVK_ANSI_2, "pick3": kVK_ANSI_3]
        let activityIds = Dictionary(uniqueKeysWithValues: activityCodes.keys.sorted().enumerated().map { ($1, UInt32(20 + $0)) })
        c.onActivityKeys = { [hotkeys] keys in
            for (name, id) in activityIds where !keys.contains(name) { hotkeys.unregister(id: id) }
            // Reply is Command+R, the rest Command+Option and a key.
            for name in keys { if let code = activityCodes[name], let id = activityIds[name] { hotkeys.register(keyCode: code, modifiers: name == "reply" ? cmdKey : cmdKey | optionKey, id: id) { c.activityKey(name) } } }
        }
        hotkeys.onChordTap = { c.chordTap() }
        c.onAccessibilityGranted = { [hotkeys] in hotkeys.restartChordMonitor() }
        hotkeys.startChordMonitor()

        if !sample {
            var seconds: TimeInterval = 20 * 60
            if let i = args.firstIndex(of: "--idle"), args.indices.contains(i + 1), let v = TimeInterval(args[i + 1]) { seconds = v }
            let monitor = ActivityMonitor(threshold: seconds)
            if !args.contains("--idle") { monitor.threshold = TimeInterval(Prefs.idleMinutes * 60) }
            c.onIdleMinutesChanged = { [weak monitor] m in monitor?.threshold = TimeInterval(m * 60) }
            c.onMenuIcon = { [weak self] image in self?.statusItem?.button?.image = image }
            monitor.onReturn = { since in c.comeBack(proactive: true, awaySince: since) }
            activity = monitor
            installStatusItem()
            // First run (or a restart in the middle of setup): the guided onboarding.
            if let step = Prefs.resumeStep { Prefs.resumeStep = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { c.startOnboarding(step: step) } }
            else if !Prefs.onboarded { DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { c.startOnboarding() } }
        }

        if let i = args.firstIndex(of: "--snapshot"), args.indices.contains(i + 1) {
            let dir = args[i + 1]
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { c.snapshot(to: dir + "/idle.png") }
            if let w = args.firstIndex(of: "--wallpaper"), args.indices.contains(w + 1) { c.snapshotWallpaper = NSImage(contentsOfFile: args[w + 1]) }
            c.holdOpen = true   // a click elsewhere while it runs must not close the card mid-capture
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { c.comeBack() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.2) { c.snapshot(to: dir + "/ask.png") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { c.send(.next) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { c.snapshot(to: dir + "/card.png") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.3) { c.send(.openSwitcher) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { c.snapshot(to: dir + "/list.png") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.4) { c.send(.dismiss) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.8) { c.showSetup() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 12.4) { c.snapshot(to: dir + "/setup.png") }
            // The live activity: a session you are not in finishes while you work.
            DispatchQueue.main.asyncAfter(deadline: .now() + 12.8) { c.send(.dismiss) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 13.6) { c.playActivityDemo() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 15.6) { c.snapshot(to: dir + "/activity.png", top: 105) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 16.4) { NSApp.terminate(nil) }
        }
        // The README's GIF (scripts/record.sh): back to a card that asks, a flip to a session at work, the list, then a
        // session you are not in finishing while you work. Sample data over a wallpaper, recorded as frames.
        if let i = args.firstIndex(of: "--record"), args.indices.contains(i + 1) {
            let dir = args[i + 1]
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            if let w = args.firstIndex(of: "--wallpaper"), args.indices.contains(w + 1) { c.snapshotWallpaper = NSImage(contentsOfFile: args[w + 1]) }
            c.holdOpen = true
            let at = { (t: Double, f: @escaping @MainActor () -> Void) in DispatchQueue.main.asyncAfter(deadline: .now() + t) { f() } }
            at(1.2) { c.record(to: dir, seconds: 19.5) }
            at(2.0) { c.comeBack() }
            at(5.0) { c.send(.next) }
            at(7.0) { c.send(.next) }   // the session at work, with its orb
            at(10.4) { c.send(.openSwitcher) }
            at(11.6) { c.send(.next) }
            at(12.4) { c.send(.previous) }
            at(13.6) { c.send(.dismiss) }
            at(14.4) { c.playActivityDemo() }
            at(21.2) { NSApp.terminate(nil) }
        }
        if args.contains("--simulate") {
            // "I was away, I'm back": asleep for a few seconds, then you return and the card stays open.
            c.holdOpen = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { c.comeBack() }
        }
        if args.contains("--setup") { DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { c.showSetup() } }
        // Replays the onboarding from the hello, without forgetting your settings.
        // The hello beside the notch after setup, and its run home behind it.
        if args.contains("--hello") { DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { c.sayHello() } }
        if args.contains("--onboarding") { DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { c.startOnboarding() } }
        // The live activity over your real sessions: a finish, a command to allow, a question.
        if args.contains("--activity") { DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { c.playActivityDemo() } }
        if args.contains("--show") { DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { c.comeBack() } }
        if args.contains("--demo") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { c.comeBack() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { c.confirm() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 12.0) { NSApp.terminate(nil) }
        }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // Until the page draws your own character (onMenuIcon), a little dome with eyes.
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { r in
            let p = NSBezierPath()
            p.move(to: NSPoint(x: 3, y: 3)); p.line(to: NSPoint(x: 3, y: 9))
            p.appendArc(withCenter: NSPoint(x: 9, y: 9), radius: 6, startAngle: 180, endAngle: 0, clockwise: true)
            p.line(to: NSPoint(x: 15, y: 3)); p.close()
            p.appendOval(in: NSRect(x: 5.6, y: 6.4, width: 2.2, height: 3.6)); p.appendOval(in: NSRect(x: 10.2, y: 6.4, width: 2.2, height: 3.6))
            p.windingRule = .evenOdd
            NSColor.black.setFill(); p.fill(); return true
        }
        image.isTemplate = true
        item.button?.image = image
        let menu = NSMenu()
        menu.addItem(withTitle: "Where was I", action: #selector(showWelcome), keyEquivalent: "").target = self
        menu.addItem(withTitle: "All sessions", action: #selector(showSwitcher), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Customize your character…", action: #selector(customize), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Choose apps…", action: #selector(chooseApps), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Set up Perch…", action: #selector(showOnboarding), keyEquivalent: "").target = self
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
    @objc private func customize() { controller?.startOnboarding(step: 1, characterOnly: true) }
    @objc private func chooseApps() { controller?.startOnboarding(step: 3) }
    @objc private func showOnboarding() { controller?.startOnboarding() }
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
