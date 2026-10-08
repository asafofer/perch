import AppKit
import WebKit
import ServiceManagement
import PerchCore

/// Owns the state machine, the transparent panel, and the web view that draws the card.
@MainActor
final class NotchController: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private let panel = NotchPanel()
    private let web: WKWebView
    private var machine: NotchMachine
    private var projects: [Project]
    private let provider: SessionProviding
    private var screen: NSScreen
    private var info: ScreenInfo
    private var contentSize = CGSize(width: NotchGeometry.cardWidth, height: 160)
    private var timerToken = 0
    private var timer: Task<Void, Never>?
    private var keyMonitor: Any?
    private var mouseMonitors: [Any] = []
    private var ready = false
    private var iconsSent = false
    private var activity: NSObjectProtocol?
    private var snoozeTask: Task<Void, Never>?
    private var hoverTask: Task<Void, Never>?
    /// The cursor is on the tab or notch, so it leans toward you.
    private var tabHot = false
    /// When the cursor left a hover-opened card. It closes only if it stays away for a moment.
    private var leftCardAt: Date?
    /// Opened by resting on the notch: no countdown, and it closes the moment the cursor leaves the card.
    private var openedByHover = false
    private var openedAt = Date.distantPast
    /// Perch spoke up on its own: it must not take the keyboard from whatever you are typing in. A click gives it focus.
    private var proactiveOpen = false
    /// The "Remind me in" choices are showing in place of the buttons.
    private var snoozeMenuOpen = false
    /// The reply field is showing; keys go to it.
    private var replyOpen = false
    private var askedForAccessibility = false
    /// After a card closes, hovering won't reopen it until the cursor has left the notch once.
    private var hoverLatched = false
    /// Simulation mode: the welcome card stays until you act on it.
    var holdOpen = false
    /// How long "Not now" hides the card before it comes back.
    var snoozeSeconds: Double = 30 * 60

    init(provider: SessionProviding) {
        self.provider = provider
        projects = []
        machine = NotchMachine(projectCount: 0)
        screen = ScreenChooser.home()
        info = screen.screenInfo
        // Without this macOS naps an app with no visible window, which makes cursor polling erratic.
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical], reason: "Watching the cursor for the notch")

        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        config.userContentController = controller
        web = WKWebView(frame: .zero, configuration: config)
        super.init()
        controller.add(WeakHandler(self), name: "perch")
        web.setValue(false, forKey: "drawsBackground")
        web.underPageBackgroundColor = .clear
        web.navigationDelegate = self
        panel.contentView = web
        place(on: screen)
        panel.orderFrontRegardless()

        if let index = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "ui") {
            web.loadFileURL(index, allowingReadAccessTo: index.deletingLastPathComponent())
        } else {
            NSLog("Perch: ui/index.html is missing from the app bundle")
        }
        installMouseMonitors()
        startRefreshing()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { guard let self, self.machine.phase == .idle else { return }; self.place(on: ScreenChooser.current()); self.push() }
        }
    }

    // MARK: public actions
    /// `proactive` is Perch speaking up on its own (you came back from being away, a snooze ended). Then it never
    /// talks about the session you are already in: that one goes to the back, and if it is the only one, nothing shows.
    func comeBack(onHome: Bool = false, proactive: Bool = false) {
        if proactive, machine.phase == .idle, let i = activeProjectIndex() {
            guard projects.count > 1 else { return }
            projects.append(projects.remove(at: i))
        }
        snoozeTask?.cancel(); openedByHover = onHome; proactiveOpen = proactive; openedAt = Date(); leftCardAt = nil; prepareToShow(onHome: onHome); send(.comeBack)
        refreshProjects()   // the card shows what we have now and updates itself a moment later
    }

    /// The most recent session of whichever app is in front: Claude, Codex or a terminal.
    private func activeProjectIndex() -> Int? {
        guard let bid = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return nil }
        let terminals: Set<String> = ["com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty", "com.github.wez.wezterm", "net.kovidgoyal.kitty"]
        return projects.firstIndex { p in
            switch bid {
            case "com.anthropic.claudefordesktop": return p.app == "claude" && p.desktopSessionId != nil
            case "com.openai.codex": return p.app == "codex"
            default: return terminals.contains(bid) && p.app == "claude" && p.desktopSessionId == nil
            }
        }
    }
    /// Command+Option tapped: open the list, or close whatever is showing.
    func chordTap() { if machine.phase == .idle { toggleSwitcher() } else { send(.dismiss) } }
    func toggleSwitcher() { openedByHover = false; proactiveOpen = false; prepareToShow(); send(.openSwitcher); refreshProjects() }
    func confirm() { send(.confirm) }

    /// Guided setup for on-device summaries. Watches the system live and finishes by itself.
    func showSetup() {
        guard machine.phase == .idle, AppleRecapEngine.setupState != "ready" else { return }
        snoozeTask?.cancel(); openedByHover = false; proactiveOpen = false; place(on: ScreenChooser.current()); send(.openSetup)
    }

    /// Debug: write the web view's current pixels to a PNG, composited over a desktop-like colour.
    func snapshot(to path: String) {
        let cfg = WKSnapshotConfiguration(); cfg.snapshotWidth = NSNumber(value: Double(web.bounds.width) * 2)
        web.takeSnapshot(with: cfg) { image, _ in
            guard let image else { return }
            let size = image.size
            let out = NSImage(size: size)
            out.lockFocus()
            NSColor(calibratedRed: 0.13, green: 0.19, blue: 0.18, alpha: 1).setFill()
            NSRect(origin: .zero, size: size).fill()
            image.draw(in: NSRect(origin: .zero, size: size))
            out.unlockFocus()
            if let tiff = out.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: path)) }
        }
    }

    // MARK: state
    private func prepareToShow(onHome: Bool = false) {
        guard machine.phase == .idle else { return }
        applyCachedRecaps()
        place(on: onHome ? ScreenChooser.home() : ScreenChooser.current())
    }

    // MARK: keeping the project list fresh, off the main thread
    private var refreshing = false
    private var pendingProjects: [Project]?

    /// Reading sessions and running git takes seconds, so it never happens when the card opens.
    func refreshProjects() {
        guard !refreshing else { refreshAgain = true; return }
        refreshing = true; refreshAgain = false
        let provider = self.provider
        Task.detached(priority: .utility) { [weak self] in
            let list = provider.parkedProjects()
            await MainActor.run {
                guard let self else { return }
                self.refreshing = false
                switch self.machine.phase {
                case .idle: self.install(list)
                case .open, .switcher: self.installLive(list)
                case .onboarding, .settings: self.projects = list; self.machine.send(.projectsChanged(count: list.count, selected: 0)); self.push()
                default: self.pendingProjects = list
                }
                if self.refreshAgain { self.refreshAgain = false; self.refreshProjects() }
            }
        }
    }
    private var refreshAgain = false

    // MARK: watching the session folders, so a new message shows up within a moment
    private var fsStream: FSEventStreamRef?
    private var fsPending = false

    private func startWatching() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let paths = [".claude/projects", ".codex/sessions"].map { home.appendingPathComponent($0).path }.filter { FileManager.default.fileExists(atPath: $0) }
        guard !paths.isEmpty else { return }
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let me = Unmanaged<NotchController>.fromOpaque(info).takeUnretainedValue()
            MainActor.assumeIsolated { me.sessionFilesChanged() }
        }
        guard let stream = FSEventStreamCreate(nil, callback, &ctx, paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.2,
                                               FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)) else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        fsStream = stream
    }

    /// A busy session writes many times a second, so refreshes are spaced at least half a second apart.
    private func sessionFilesChanged() {
        guard !fsPending else { return }
        fsPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            MainActor.assumeIsolated { self?.fsPending = false; self?.refreshProjects() }
        }
    }

    /// New data while the card is up: swap it in, keep the same project selected, and redraw.
    private func installLive(_ list: [Project]) {
        guard list != projects else { return }
        let keep = projects.indices.contains(machine.selected) ? projects[machine.selected].id : nil
        projects = list
        machine.send(.projectsChanged(count: list.count, selected: list.firstIndex { $0.id == keep } ?? 0))
        applyCachedRecaps()
        enrich()
        push()
    }

    private func install(_ list: [Project]) {
        projects = list
        machine.projectCount = list.count
        applyCachedRecaps()
        enrich()
        push()
    }

    private func startRefreshing() {
        // Switching apps changes which session counts as "the one you are in", so the resting character is re-evaluated.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.machine.phase == .idle { self?.push() } }
        }
        refreshProjects()
        startWatching()
        // Every 5 seconds while the card is up, every 20 otherwise.
        var tick = 0
        let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                tick += 1
                if self.machine.phase == .open || self.machine.phase == .switcher || tick % 4 == 0 { self.refreshProjects() }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshProjects() }
        }
    }

    // MARK: on-device recaps
    private var enriching = false

    /// Cached model-written recaps apply instantly.
    private func applyCachedRecaps() {
        guard let real = provider as? RealSessionProvider else { return }
        for i in projects.indices {
            if let input = real.inputs[projects[i].id], let key = RecapCache.key(for: input.digest), let r = RecapCache.shared.get(key) {
                projects[i] = RecapMerge.apply(r, to: projects[i], grounding: input.digest)
            }
        }
    }

    /// Writes missing recaps with the on-device model, one at a time, and updates the card as each lands.
    func enrich() {
        guard !enriching, let real = provider as? RealSessionProvider, AppleRecapEngine.unavailableReason == nil else { return }
        let todo = projects.compactMap { p -> (String, SessionDigest, GitInfo?, String, String, String)? in
            guard let input = real.inputs[p.id], let key = RecapCache.key(for: input.digest), RecapCache.shared.get(key) == nil else { return nil }
            return (p.id, input.digest, input.git, p.name, key, p.app == "codex" ? "Codex" : "Claude")
        }
        guard !todo.isEmpty else { return }
        enriching = true
        Task { [weak self] in
            for (id, digest, git, name, key, agent) in todo {
                guard let r = await AppleRecapEngine.recap(digest: digest, git: git, name: name, agent: agent) else { continue }
                RecapCache.shared.set(key, r)
                guard let self, let i = self.projects.firstIndex(where: { $0.id == id }) else { continue }
                self.projects[i] = RecapMerge.apply(r, to: self.projects[i], grounding: digest)
                self.push()
            }
            self?.enriching = false
        }
    }

    private func place(on s: NSScreen) {
        screen = s; info = s.screenInfo
        panel.setFrame(NotchGeometry.panelFrame(for: info), display: true)
    }

    func send(_ event: NotchEvent) {
        // Pick up does the job and gets out of the way: no success screen.
        if machine.phase == .open || machine.phase == .switcher {
            switch event {
            case .confirm: pickUp(machine.selected); return
            case .choose(let i): pickUp(i); return
            default: break
            }
        }
        let old = machine.phase
        machine.send(event)
        if machine.phase != old { phaseChanged(old, machine.phase) }
        push()
    }

    private func pickUp(_ index: Int) {
        guard projects.indices.contains(index) else { return }
        Restorer.resume(projects[index])
        let old = machine.phase
        machine.send(.dismiss)
        phaseChanged(old, machine.phase)
        push()
    }

    private func push() {
        guard ready else { return }
        let snap = UISnapshot(machine: machine, projects: projects, screen: info, timerToken: timerToken, icons: iconsSent ? nil : AppIcons.all(), setup: AppleRecapEngine.setupState, allowAutoCollapse: !holdOpen && !openedByHover && !snoozeMenuOpen && !replyOpen,
                          activeId: machine.phase == .idle ? activeProjectIndex().map { projects[$0].id } : nil,
                          onboarding: machine.phase == .onboarding ? onboardingState() : nil,
                          settings: machine.phase == .settings ? settingsState() : nil)
        iconsSent = true
        guard let data = try? JSONEncoder().encode(snap), let json = String(data: data, encoding: .utf8) else { return }
        web.evaluateJavaScript("window.perch && window.perch.apply(\(json))", completionHandler: nil)
    }

    private func phaseChanged(_ old: NotchPhase, _ new: NotchPhase) {
        if old == .onboarding { Prefs.onboarded = true; onbTask?.cancel() }
        if ProcessInfo.processInfo.environment["PERCH_TRACE"] != nil { NSLog("Perch phase: \(old) -> \(new)") }
        switch new {
        case .idle:
            hoverLatched = true; snoozeMenuOpen = false; replyOpen = false
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(700))
                guard let self, self.machine.phase == .idle else { return }
                self.place(on: ScreenChooser.current())
                if let pending = self.pendingProjects { self.pendingProjects = nil; self.install(pending) } else { self.push() }
                self.refreshProjects()
            }
            timer?.cancel(); stopKeys(); panel.allowsKey = false; panel.ignoresMouseEvents = true
        case .open:
            startKeys(); panel.allowsKey = true; panel.ignoresMouseEvents = false; if !openedByHover && !proactiveOpen { panel.makeKey() }
            restartTimer()
        case .switcher:
            timer?.cancel()
            startKeys(); panel.allowsKey = true; panel.ignoresMouseEvents = false; if !openedByHover && !proactiveOpen { panel.makeKey() }
        case .onboarding:
            startKeys(); panel.allowsKey = true; panel.ignoresMouseEvents = false; panel.makeKey()
            watchOnboarding()
        case .settings:
            startKeys(); panel.allowsKey = true; panel.ignoresMouseEvents = false; panel.makeKey()
            watchOnboarding()
        case .setup:
            startKeys(); panel.allowsKey = true; panel.ignoresMouseEvents = false; if !openedByHover && !proactiveOpen { panel.makeKey() }
            watchSetup()
        case .restoring:
            timer?.cancel()
            timer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(3.2))
                if !Task.isCancelled { self?.send(.restoreFinished) }
            }
        }
    }


    /// While the setup card is open, re-check the system every second and close the card once everything is ready.
    private func watchSetup() {
        timer?.cancel()
        timer = Task { [weak self] in
            var last = ""
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.machine.phase == .setup else { return }
                let now = AppleRecapEngine.setupState
                if now != last { last = now; self.push() }
                if now == "ready" {
                    try? await Task.sleep(for: .seconds(2.2))
                    if self.machine.phase == .setup { self.send(.dismiss) }
                    self.enrich(); return
                }
            }
        }
    }

    private func restartTimer() {
        timer?.cancel(); timerToken += 1
        guard machine.autoCollapses, !holdOpen, !openedByHover, !snoozeMenuOpen, !replyOpen else { return }
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(9))
            if !Task.isCancelled { self?.send(.timeout) }
        }
    }

    // MARK: web view
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { ready = true; push() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) { NSLog("Perch: web load failed: \(error)") }

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "confirm": send(.confirm)
        case "dismiss": send(.dismiss)
        case "snooze": snooze(body["when"] as? String ?? "30m")
        case "replyMenu":
            replyOpen = body["open"] as? Bool ?? false
            if replyOpen { timer?.cancel(); panel.makeKey() } else { restartTimer() }
            push()
        case "reply": if let t = body["text"] as? String { reply(t) }
        case "snoozeMenu":
            snoozeMenuOpen = body["open"] as? Bool ?? false
            if snoozeMenuOpen { timer?.cancel() } else { restartTimer() }
            push()
        case "switcher": send(.openSwitcher)
        case "back": send(.back)
        case "onb": if let a = body["action"] as? String { onboardingAction(a) }
        case "settings": if machine.phase == .idle { place(on: ScreenChooser.current()); proactiveOpen = false; openedByHover = false }; send(.openSettings)
        case "setting":
            if let key = body["key"] as? String {
                if key == "idleMinutes", let v = body["value"] as? Int { Prefs.idleMinutes = v; onIdleMinutesChanged?(v) }
                if key == "login", let on = body["value"] as? Bool { setLaunchAtLogin(on) }
                push()
            }
        case "onbOpen":
            let step = body["step"] as? Int ?? 0
            send(.dismiss)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.startOnboarding(step: step) }
        case "quit": NSApp.terminate(nil)
        case "source":
            if let id = body["id"] as? String, let on = body["enabled"] as? Bool {
                var set = Prefs.enabledSources
                if on { set.insert(id) } else { set.remove(id) }
                Prefs.enabledSources = set
                refreshProjects(); push()
            }
        case "character":
            if let shape = body["shape"] as? String { Prefs.shape = shape }
            if let color = body["color"] as? String { Prefs.color = color }
        case "openSettings": NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")!)
        case "choose": if let i = body["index"] as? Int { send(.choose(i)) }
        case "size":
            if let w = body["width"] as? Double, let h = body["height"] as? Double { contentSize = CGSize(width: w, height: h) }
        case "log": NSLog("Perch UI: \(body["text"] ?? "")")
        default: break
        }
    }

    /// "Not now": hide the card and bring it back later (30 minutes, 2 hours, or 9 in the morning), unless you come back to it yourself first.
    private func snooze(_ when: String) {
        let seconds: Double
        switch when {
        case "2h": seconds = 2 * 3600
        case "tomorrow":
            let cal = Calendar.current
            let next = cal.nextDate(after: Date(), matching: DateComponents(hour: 9, minute: 0), matchingPolicy: .nextTime) ?? Date().addingTimeInterval(12 * 3600)
            // "Tomorrow" means tomorrow even when it is 5 AM now.
            let tomorrow = cal.isDateInToday(next) ? cal.date(byAdding: .day, value: 1, to: next) ?? next : next
            seconds = max(60, tomorrow.timeIntervalSinceNow)
        default: seconds = snoozeSeconds
        }
        send(.dismiss)
        snoozeTask?.cancel()
        snoozeTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled, self.machine.phase == .idle { self.comeBack(proactive: true) }
        }
    }

    /// Answers Claude or Codex without typing in its window: the reply goes on the clipboard, the exact session opens, and it is
    /// pasted and sent for you when Perch has Accessibility access. Without it, it stays on the clipboard for you to paste.
    private func reply(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents(); pb.setString(text, forType: .string)
        let project = projects.indices.contains(machine.selected) ? projects[machine.selected] : nil
        pickUp(machine.selected)
        // Typing into another app needs Accessibility. Ask once per launch (never in a loop). The paste is attempted
        // either way, and the reply stays on the clipboard if it cannot go through.
        let trusted = AXIsProcessTrusted()
        if !trusted, !askedForAccessibility {
            askedForAccessibility = true
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        }
        NSLog("Perch: reply, accessibility trusted = \(trusted)")
        let target = project?.app == "codex" ? "com.openai.codex" : (project?.desktopSessionId != nil ? "com.anthropic.claudefordesktop" : "com.apple.Terminal")
        Task {
            // Wait for the app to be in front (up to 5 s), then give its message box a moment to take focus.
            for _ in 0..<50 {
                if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == target { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            try? await Task.sleep(for: .milliseconds(800))
            let src = CGEventSource(stateID: .combinedSessionState)
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: down)
                e?.flags = .maskCommand
                e?.post(tap: .cghidEventTap)
            }
            // You wrote it and pressed Send, so it is sent: Return after the paste.
            try? await Task.sleep(for: .milliseconds(250))
            for down in [true, false] {
                CGEvent(keyboardEventSource: src, virtualKey: 36, keyDown: down)?.post(tap: .cghidEventTap)
            }
            NSLog("Perch: sent reply into \(target)")
        }
    }

    // MARK: settings
    var onIdleMinutesChanged: ((Int) -> Void)?

    private func settingsState() -> UISnapshot.Settings {
        let counts = (provider as? RealSessionProvider)?.counts ?? [:]
        let on = Prefs.enabledSources
        let sources = [("claude", "Claude Code"), ("codex", "Codex")].map { id, name in
            UISnapshot.Source(id: id, name: name, count: counts[id]?.count ?? 0, names: counts[id]?.names ?? [], enabled: on.contains(id))
        }
        return UISnapshot.Settings(sources: sources, summaries: AppleRecapEngine.setupState, accessibility: AXIsProcessTrusted(),
                                   idleMinutes: Prefs.idleMinutes, login: SMAppService.mainApp.status == .enabled)
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        catch { NSLog("Perch: launch at login failed: \(error)") }
    }

    // MARK: onboarding
    var onAccessibilityGranted: (() -> Void)?
    private var onbStep = 0
    private let onbTotal = 5
    private var accessibilityWas = AXIsProcessTrusted()
    private var onbTask: Task<Void, Never>?

    func startOnboarding(step: Int = 0) {
        guard machine.phase == .idle else { return }
        onbStep = step; snoozeTask?.cancel(); openedByHover = false; proactiveOpen = false
        place(on: ScreenChooser.current())
        if step >= 2 { refreshProjects() }
        send(.openOnboarding)
    }

    private func onboardingState() -> UISnapshot.Onboarding {
        let counts = (provider as? RealSessionProvider)?.counts ?? [:]
        let on = Prefs.enabledSources
        let sources = [("claude", "Claude Code"), ("codex", "Codex")].map { id, name in
            UISnapshot.Source(id: id, name: name, count: counts[id]?.count ?? 0, names: counts[id]?.names ?? [], enabled: on.contains(id))
        }
        return UISnapshot.Onboarding(step: onbStep, total: onbTotal, accessibility: AXIsProcessTrusted(), summaries: AppleRecapEngine.setupState, scanning: refreshing, sources: sources)
    }

    private func onboardingAction(_ action: String) {
        switch action {
        case "next":
            onbStep = min(onbStep + 1, onbTotal - 1)
            if onbStep == 2 { refreshProjects() }
        case "back": onbStep = max(onbStep - 1, 0)
        case "finish": send(.dismiss); return
        case "accessibility":
            // Asking is what lists Perch in the Accessibility pane; then take them there.
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        case "restart": relaunch(); return
        default: break
        }
        push()
    }

    /// Starts a fresh copy of Perch and quits this one. Some permissions only apply to a new process.
    private func relaunch() {
        Prefs.resumeStep = onbStep
        let task = Process(); task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.8; open -n \"\(Bundle.main.bundlePath)\""]
        try? task.run()
        NSApp.terminate(nil)
    }

    /// While onboarding is up, notice permission changes within a second so the card reacts as you click in System Settings.
    private func watchOnboarding() {
        onbTask?.cancel()
        onbTask = Task { [weak self] in
            var last = ""
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(700))
                guard let self, self.machine.phase == .onboarding || self.machine.phase == .settings else { return }
                let trusted = AXIsProcessTrusted()
                if trusted, !self.accessibilityWas { self.accessibilityWas = true; self.onAccessibilityGranted?() }
                let key = "\(trusted)|\(AppleRecapEngine.setupState)|\(self.refreshing)|\(self.projects.count)|\(Prefs.enabledSources.sorted())"
                if key != last { last = key; self.push() }
            }
        }
    }

    // MARK: keys
    private func startKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, self.machine.phase != .idle else { return e }
            if self.machine.phase == .onboarding {
                switch e.keyCode {
                case 36, 76: self.web.evaluateJavaScript("window.perch && window.perch.onbKey('enter')", completionHandler: nil)
                case 123: self.web.evaluateJavaScript("window.perch && window.perch.onbKey('left')", completionHandler: nil)
                case 124: self.web.evaluateJavaScript("window.perch && window.perch.onbKey('right')", completionHandler: nil)
                case 53: self.send(.dismiss)
                default: return e
                }
                return nil
            }
            if self.replyOpen {
                if e.keyCode == 53 { self.web.evaluateJavaScript("window.perch && window.perch.replyMenu(false)", completionHandler: nil); return nil }
                return e
            }
            if self.snoozeMenuOpen {
                switch e.keyCode {
                case 18: self.snooze("30m")
                case 19: self.snooze("2h")
                case 20: self.snooze("tomorrow")
                case 53, 45, 48, 36, 76: self.web.evaluateJavaScript("window.perch && window.perch.snoozeMenu(false)", completionHandler: nil)
                default: return e
                }
                return nil
            }
            switch e.keyCode {
            case 36, 76: self.send(.confirm)
            case 53: self.send(.dismiss)
            case 43: if self.machine.phase == .open || self.machine.phase == .switcher { self.send(.openSettings) } else { return e }
            case 48: self.send(self.machine.phase == .open ? .openSwitcher : .back)
            case 15: if self.machine.phase == .open { self.web.evaluateJavaScript("window.perch && window.perch.replyMenu(true)", completionHandler: nil) } else { return e }
            case 45: if self.machine.phase == .open { self.web.evaluateJavaScript("window.perch && window.perch.snoozeMenu(true)", completionHandler: nil) } else { return e }
            case 125: self.send(.next)
            case 126: self.send(.previous)
            default: return e
            }
            if self.machine.phase == .open { self.restartTimer(); self.push() }
            return nil
        }
    }
    private func stopKeys() { if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil } }

    // MARK: mouse. Hover pauses the timer; the panel only catches clicks over the visible card.
    private var cursorTimer: Timer?
    private var lastCursor = CGPoint(x: -1, y: -1)

    /// Checks the cursor 30 times a second. Reliable where mouse-moved events are not, and it feeds the character's eyes.
    private func startCursorPolling() {
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.mouseMoved()
                let p = NSEvent.mouseLocation
                if self.machine.phase != .idle, self.ready, p != self.lastCursor {
                    self.lastCursor = p
                    let f = self.panel.frame
                    self.web.evaluateJavaScript("window.perch && window.perch.cursor(\(p.x - f.minX), \(f.maxY - p.y))", completionHandler: nil)
                }
            }
        }
        t.tolerance = 0
        RunLoop.main.add(t, forMode: .common)
        cursorTimer = t
    }

    /// A click anywhere outside the card closes it.
    private func clickedElsewhere() {
        guard machine.phase != .idle, machine.phase != .onboarding, machine.phase != .settings else { return }
        let rect = NotchGeometry.contentRect(width: contentSize.width, height: contentSize.height, screen: info)
        if !rect.contains(NSEvent.mouseLocation) { send(.dismiss) }
    }

    private func installMouseMonitors() {
        startCursorPolling()
        if let g = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] _ in MainActor.assumeIsolated { self?.clickedElsewhere() } }) { mouseMonitors.append(g) }
        let handler: (NSEvent?) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.mouseMoved() } }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: handler) { mouseMonitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { e in handler(e); return e }) { mouseMonitors.append(l) }
    }
    /// The notch plus a little room for the character beside it.
    private func notchHoverRect() -> CGRect {
        let idle = NotchGeometry.idleSize(for: info)
        let w = max(idle.width, 150)
        let left: CGFloat = 30, right: CGFloat = 8     // the character sits just left of the notch
        // Extends above the screen edge so the very top pixel row of the cursor counts.
        return CGRect(x: info.frame.midX - w / 2 - left, y: info.frame.maxY - idle.height - 2, width: w + left + right, height: idle.height + 40)
    }

    /// Resting the cursor on the notch for a moment opens the welcome card.
    private func hoverIdle() {
        let inside = notchHoverRect().contains(NSEvent.mouseLocation)
        if inside != tabHot { tabHot = inside; web.evaluateJavaScript("window.perch && window.perch.hot(\(inside))", completionHandler: nil) }
        if !inside { hoverLatched = false; hoverTask?.cancel(); hoverTask = nil; return }
        if hoverLatched || hoverTask != nil || NSEvent.pressedMouseButtons != 0 { return }
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard let self, !Task.isCancelled else { return }
            self.hoverTask = nil
            if ProcessInfo.processInfo.environment["PERCH_TRACE"] != nil { NSLog("Perch hover: dwell done") }
            if self.machine.phase == .idle, self.notchHoverRect().contains(NSEvent.mouseLocation) { self.comeBack(onHome: true) }
        }
    }

    private func mouseMoved() {
        if machine.phase == .idle {
            // The tab (or notch) lives on whichever screen the cursor is on, so an external display gets one too.
            if let under = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }), under !== screen { place(on: under); push() }
            hoverIdle(); return
        }
        let rect = NotchGeometry.contentRect(width: contentSize.width, height: contentSize.height, screen: info)
        let inside = rect.contains(NSEvent.mouseLocation)
        panel.ignoresMouseEvents = !inside
        if inside, panel.allowsKey, !panel.isKeyWindow, !proactiveOpen { panel.makeKey() }
        if openedByHover, Date().timeIntervalSince(openedAt) > 0.5 {
            // A few points of slack and a quarter second, so drifting off an edge does not slam it shut.
            if rect.insetBy(dx: -10, dy: -10).contains(NSEvent.mouseLocation) { leftCardAt = nil }
            else if let t = leftCardAt { if Date().timeIntervalSince(t) > 0.25 { leftCardAt = nil; send(.dismiss); return } }
            else { leftCardAt = Date() }
        }
        if inside != machine.hovering {
            send(.hoverChanged(inside))
            if machine.phase == .open { restartTimer(); push() }
        }
    }
}

/// WKUserContentController retains its handlers; this keeps the controller from being retained by the web view.
final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ t: WKScriptMessageHandler) { target = t }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) { target?.userContentController(c, didReceive: m) }
}
