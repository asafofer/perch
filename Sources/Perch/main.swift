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
            // Names after the flag limit it to those agents (`--install-hooks cursor`).
            let given = args.drop(while: { $0 != flag }).dropFirst().filter { !$0.hasPrefix("-") }
            // A name that is no agent is a typo: nothing is changed (no names at all means every agent).
            if let bad = given.first(where: { !HookInstaller.agents.contains($0) }) { print("unknown agent \(bad); known: \(HookInstaller.agents.joined(separator: ", "))"); exit(1) }
            let named = given
            for agent in HookInstaller.agents where named.isEmpty || named.contains(agent) {
                do { if flag == "--install-hooks" { try HookInstaller.install(agent) } else { try HookInstaller.uninstall(agent) } ; print("\(agent): \(HookInstaller.isInstalled(agent) ? "on" : "off")") }
                catch { print("\(agent): \(error.localizedDescription)") }
            }
            exit(0)
        }
        // The design page draws stand-in icons; this writes this Mac's real ones next to it (git ignores the file).
        if let i = args.firstIndex(of: "--design-icons") {
            let out = URL(fileURLWithPath: i + 1 < args.count ? args[i + 1] : "ui/icons.local.json")
            let icons = AppIcons.all().merging(AppIcons.designFiles(wallpaper: out.deletingLastPathComponent().appendingPathComponent("wallpapers/blue-distortion-1.webp"))) { a, _ in a }
            do { try JSONSerialization.data(withJSONObject: icons, options: [.sortedKeys]).write(to: out); print("wrote \(out.path)") }
            catch { print("could not write \(out.path): \(error)") }
            exit(0)
        }
        if args.contains("--dump") {
            for s in NSScreen.screens { print("screen: \(s.localizedName) | \(s.displayID) | notch: \(s.notchSize != nil ? "yes" : "no")") }
            print("show on: \(Prefs.showOn.raw) -> \(ScreenChooser.target().localizedName)")
            // Pull requests: ask whether the GitHub CLI works, and with Checks on let GitHub answer once before the list is printed.
            let pulls = PullRequestState.shared
            pulls.refreshAvailability(force: true); Thread.sleep(forTimeInterval: 2)
            if pulls.mode == .checks { _ = RealSessionProvider().parkedProjects(); Thread.sleep(forTimeInterval: 10) }
            print("pull requests: \(pulls.mode.rawValue) (GitHub CLI: \(pulls.availability.map { "\($0)" } ?? "not asked"))")
            for p in RealSessionProvider().parkedProjects() {
                let opens = p.conductor != nil ? "Conductor, workspace \(p.conductor ?? "?")" : p.terminal ? "\(p.via ?? Terminals.preferred)\(p.host.map { " (\($0))" } ?? ""): \(p.pid.map { "running, pid \($0)" } ?? Agent.of(p.app).resume(p.sessionId ?? "?"))"
                    : p.app == "codex" ? "codex://threads/\(p.sessionId ?? "?")" : Restorer.link(p)?.absoluteString ?? "?"
                print("\(p.name) | \(p.branch ?? "-") | left \(p.at) (\(p.away) ago) | \(p.status.kind): \(p.status.text)")
                print("   headline: \(p.headline)\n   context:  \(p.context)\n   next:     \(p.next)\n   opens:    \(opens)")
                if !p.prs.isEmpty { print("   pull requests: " + p.prs.map { "#\($0.number) \($0.state.rawValue)\($0.needsYou ? " (needs you)" : "")" }.joined(separator: ", ")) }
            }
            let (hits, viewers) = LiveSessions.scan()
            for hit in hits {
                let place: String
                switch hit.place {
                case .herdr(let pane, _, let session): place = "herdr \(session) pane \(pane)" + (hit.viewer.map { ", shown on \($0.tty)" } ?? ", no herdr client attached")
                case .tmux(let pane, _): place = "tmux \(hit.tmuxSession ?? "?") pane \(pane)" + (hit.viewer.map { ", shown on \($0.tty)" } ?? ", no tmux client attached")
                case .cmux(let w, let s): place = "cmux workspace \(w.prefix(8)) surface \(s.prefix(8))"
                case .agterm(_, let s, let pane): place = "agterm session \(s.prefix(8)) pane \(pane.prefix(8))"
                case .tab: place = "a tab"
                }
                print("running: \(hit.agent) pid \(hit.pid) in \(hit.cwd) on \(hit.tty), \(place), in \(hit.app ?? "no app")")
            }
            for v in viewers { print("\(v.tmux == nil ? "herdr" : "tmux") client: session \(v.session) on \(v.tty) in \(v.app ?? "no app")") }
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
        updater.onWhatsNew = { [weak c] version, notes in c?.showWhatsNew(version: version, notes: notes) }
        // What is new has one key, Command+Option+Return, registered only while the card shows.
        c.onWhatsNewKey = { [hotkeys] on in
            if on { hotkeys.register(keyCode: kVK_Return, modifiers: cmdKey | optionKey, id: 40) { c.whatsNewDone() } } else { hotkeys.unregister(id: 40) }
        }
        // --whats-new plays the card with this build's notes (or the demo's), as the first start on a new version would.
        if args.contains("--whats-new") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [updater] in c.showWhatsNew(version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "", notes: updater.bundledNotes ?? Updater.demoNotes) }
        }
        if args.contains("--update-demo") { updater.demo() } else if !sample { updater.start() }
        c.canUpdate = updater.canCheck

        hotkeys.register(keyCode: kVK_ANSI_P, modifiers: controlKey | optionKey, id: 1) { c.comeBack() }
        hotkeys.register(keyCode: kVK_ANSI_L, modifiers: controlKey | optionKey, id: 2) { c.toggleSwitcher() }
        hotkeys.register(keyCode: kVK_ANSI_Q, modifiers: controlKey | optionKey, id: 3) { NSApp.terminate(nil) }
        // A new session, from anywhere (Settings shows it under Open Perch). Id 4 is the open shortcut (HotkeyService.openId).
        let newSession = { [hotkeys] in
            let s = Prefs.newShortcut
            return hotkeys.register(keyCode: s.keyCode ?? kVK_ANSI_N, modifiers: s.mods.carbonFlags, id: 5) { c.openNewSession() }
        }
        var newWorks = newSession()
        c.onNewShortcutChanged = { newWorks = newSession() }
        c.newComboWorks = { newWorks }
        // While the notch says an answer or a request arrived, its buttons answer to Command+Option and a key. Only then.
        let activityCodes: [String: Int] = ["pick": kVK_Return, "open": kVK_Return, "reply": kVK_ANSI_R, "gone": kVK_ANSI_Period,
                                            "allow": kVK_ANSI_A, "deny": kVK_ANSI_X, "pick1": kVK_ANSI_1, "pick2": kVK_ANSI_2, "pick3": kVK_ANSI_3, "app": kVK_ANSI_O]
        let activityIds = Dictionary(uniqueKeysWithValues: activityCodes.keys.sorted().enumerated().map { ($1, UInt32(20 + $0)) })
        c.onActivityKeys = { [hotkeys] keys in
            for (name, id) in activityIds where !keys.contains(name) { hotkeys.unregister(id: id) }
            // Reply is Command+R, the rest Command+Option and a key.
            // A key Perch's own shortcuts already use, or that another app holds, is left alone: its button shows no key.
            let mine = [Prefs.openShortcut, Prefs.newShortcut].compactMap { s in s.kind == .combo && s.mods == [.command, .option] ? s.keyCode : nil }
            var missed: [String] = []
            for name in keys { if let code = activityCodes[name], let id = activityIds[name] {
                let mods = name == "reply" ? cmdKey : cmdKey | optionKey
                if mods == cmdKey | optionKey && mine.contains(code) { hotkeys.unregister(id: id); missed.append(name); continue }
                if !hotkeys.register(keyCode: code, modifiers: mods, id: id, action: { c.activityKey(name) }) { missed.append(name) }
            } }
            c.activityKeysMissed(missed)
        }
        c.onReplyKey = { [hotkeys] on in if on { hotkeys.register(keyCode: kVK_ANSI_R, modifiers: 0, id: 40) { c.replyKey() } } else { hotkeys.unregister(id: 40) } }
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
            monitor.onReturn = { [updater] since in c.comeBack(proactive: true, awaySince: since); updater.checkSoon() }
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
            // and the way back to the copy you use every day, in one click
            if let installed = installedCopy() {
                let version = Bundle(url: installed)?.infoDictionary?["CFBundleShortVersionString"] as? String
                let back = menu.addItem(withTitle: "Back to installed Perch" + (version.map { " \($0)" } ?? ""), action: #selector(backToInstalled), keyEquivalent: "")
                back.target = self; back.representedObject = installed
            }
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
    private func installedCopy() -> URL? {
        let found = Bundle.main.bundleIdentifier.map { NSWorkspace.shared.urlsForApplications(withBundleIdentifier: $0) } ?? []
        return InstalledCopy.pick(found + [URL(fileURLWithPath: "/Applications/Perch.app")].filter { FileManager.default.fileExists(atPath: $0.path) }, running: Bundle.main.bundleURL)
    }
    /// Quits this test build and opens the installed copy once it has gone: both have the same bundle id, so opening it while
    /// this one runs would only bring this one forward, and two copies would fight over the hotkeys and the hook socket.
    @objc private func backToInstalled(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? URL else { return }
        let wait = Process()
        wait.executableURL = URL(fileURLWithPath: "/bin/sh")
        wait.arguments = ["-c", "while kill -0 \(getpid()) 2>/dev/null; do sleep 0.1; done; /usr/bin/open -n \"$1\"", "sh", app.path]
        do { try wait.run() } catch { return }
        NSApp.terminate(nil)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
