import AppKit
import Carbon.HIToolbox
import PerchCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchController?
    private var activity: ActivityMonitor?
    private var statusItem: NSStatusItem?
    private let hotkeys = HotkeyService()
    private let updater = Updater()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let flag = args.first(where: { $0 == "--install-hooks" || $0 == "--uninstall-hooks" }) {
            for agent in HookInstaller.agents {
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
            for s in NSScreen.screens { print("screen: \(s.localizedName) | \(s.displayID) | notch: \(s.notchSize != nil ? "yes" : "no")") }
            print("show on: \(Prefs.showOn.raw) -> \(ScreenChooser.target().localizedName)")
            for p in RealSessionProvider().parkedProjects() {
                let opens = p.terminal ? "\(p.via ?? Terminals.preferred)\(p.host.map { " (\($0))" } ?? ""): \(p.pid.map { "running, pid \($0)" } ?? Agent.of(p.app).resume(p.sessionId ?? "?"))"
                    : p.app == "codex" ? "codex://threads/\(p.sessionId ?? "?")" : "claude://code/continue?session=\(p.desktopSessionId ?? "?")"
                print("\(p.name) | \(p.branch ?? "-") | left \(p.at) (\(p.away) ago) | \(p.status.kind): \(p.status.text)")
                print("   headline: \(p.headline)\n   context:  \(p.context)\n   next:     \(p.next)\n   opens:    \(opens)")
            }
            let (hits, viewers) = LiveSessions.scan()
            for hit in hits {
                let place: String
                switch hit.place {
                case .herdr(let pane, _, let session): place = "herdr \(session) pane \(pane)" + (hit.viewer.map { ", shown on \($0.tty)" } ?? ", no herdr client attached")
                case .cmux(let w, let s): place = "cmux workspace \(w.prefix(8)) surface \(s.prefix(8))"
                case .tab: place = "a tab"
                }
                print("running: \(hit.agent) pid \(hit.pid) in \(hit.cwd) on \(hit.tty), \(place), in \(hit.app ?? "no app")")
            }
            for v in viewers { print("herdr client: session \(v.session) on \(v.tty) in \(v.app ?? "no app")") }
            print("speak up on its own now: \(Quiet.reason().map { "no, \($0)" } ?? "yes")")
            exit(0)
        }
        HookInstaller.upgrade()
        // Demos and snapshots always use sample data, so they never open Terminal.
        let sample = args.contains("--fake") || ((args.contains("--demo") || args.contains("--snapshot")) && !args.contains("--real"))
        let provider: SessionProviding = sample ? FakeSessionProvider() : RealSessionProvider()
        let c = NotchController(provider: provider)
        controller = c
        updater.isQuiet = { [weak c] in c?.isQuiet ?? true }
        updater.onChange = { [weak c] info in c?.updateInfo = info }
        c.onUpdateAction = { [weak self] action in self?.updater.handle(action) }
        if args.contains("--update-demo") { updater.demo() } else if !sample { updater.start() }
        c.canUpdate = updater.canCheck

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
        hotkeys.apply(Prefs.openShortcut)
        c.openComboWorks = { [hotkeys] in hotkeys.openCombo }
        c.onShortcutRecording = { [hotkeys] recording in if recording { hotkeys.pauseAll() } else { hotkeys.resumeAll(); hotkeys.apply(Prefs.openShortcut) } }
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
            // The live activity: a session you are not in finishes while you work.
            DispatchQueue.main.asyncAfter(deadline: .now() + 12.8) { c.send(.dismiss) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 13.6) { c.playActivityDemo() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 15.6) { c.snapshot(to: dir + "/activity.png", top: 105) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 16.4) { NSApp.terminate(nil) }
        }
        if args.contains("--simulate") {
            // "I was away, I'm back": asleep for a few seconds, then you return and the card stays open.
            c.holdOpen = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { c.comeBack() }
        }
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
        if let test = TestBuild.label {
            // A test build says so where you cannot miss it: next to the icon, and as the menu's first line.
            item.length = NSStatusItem.variableLength
            item.button?.imagePosition = .imageLeading
            item.button?.title = " TEST"
            item.button?.toolTip = "Test build: \(test)"
            let line = menu.addItem(withTitle: "Test build: \(test)", action: nil, keyEquivalent: ""); line.isEnabled = false
            menu.addItem(.separator())
        }
        menu.addItem(withTitle: "Where was I", action: #selector(showWelcome), keyEquivalent: "").target = self
        menu.addItem(withTitle: "All sessions", action: #selector(showSwitcher), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Customize your character…", action: #selector(customize), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Choose apps…", action: #selector(chooseApps), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Set up Perch…", action: #selector(showOnboarding), keyEquivalent: "").target = self
        if let check = updater.checkItem { menu.addItem(check) }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Perch", action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu
        statusItem = item
    }
    @objc private func showWelcome() { controller?.comeBack() }
    @objc private func showSwitcher() { controller?.toggleSwitcher() }
    @objc private func customize() { controller?.startOnboarding(step: 1, characterOnly: true) }
    @objc private func chooseApps() { controller?.startOnboarding(step: 4) }
    @objc private func showOnboarding() { controller?.startOnboarding() }
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
