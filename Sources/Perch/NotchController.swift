import AppKit
import WebKit
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
    private var openedByHover = false
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
    func comeBack(onHome: Bool = false) { snoozeTask?.cancel(); openedByHover = onHome; prepareToShow(onHome: onHome); send(.comeBack) }
    func toggleSwitcher() { prepareToShow(); send(.openSwitcher) }
    func confirm() { send(.confirm) }

    /// Guided setup for on-device summaries. Watches the system live and finishes by itself.
    func showSetup() {
        guard machine.phase == .idle, AppleRecapEngine.setupState != "ready" else { return }
        snoozeTask?.cancel(); place(on: ScreenChooser.current()); send(.openSetup)
    }

    /// Debug: write the web view's current pixels to a PNG, composited over a desktop-like colour.
    func snapshot(to path: String) {
        web.takeSnapshot(with: nil) { image, _ in
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
        guard !refreshing else { return }
        refreshing = true
        let provider = self.provider
        Task.detached(priority: .utility) { [weak self] in
            let list = provider.parkedProjects()
            await MainActor.run {
                guard let self else { return }
                self.refreshing = false
                if self.machine.phase == .idle { self.install(list) } else { self.pendingProjects = list }
            }
        }
    }

    private func install(_ list: [Project]) {
        projects = list
        machine.projectCount = list.count
        applyCachedRecaps()
        enrich()
        push()
    }

    private func startRefreshing() {
        refreshProjects()
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.refreshProjects() } }
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
        let snap = UISnapshot(machine: machine, projects: projects, screen: info, timerToken: timerToken, icons: iconsSent ? nil : AppIcons.all(), setup: AppleRecapEngine.setupState, allowAutoCollapse: !holdOpen)
        iconsSent = true
        guard let data = try? JSONEncoder().encode(snap), let json = String(data: data, encoding: .utf8) else { return }
        web.evaluateJavaScript("window.perch && window.perch.apply(\(json))", completionHandler: nil)
    }

    private func phaseChanged(_ old: NotchPhase, _ new: NotchPhase) {
        if ProcessInfo.processInfo.environment["PERCH_TRACE"] != nil { NSLog("Perch phase: \(old) -> \(new)") }
        switch new {
        case .idle:
            hoverLatched = true
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(700))
                guard let self, self.machine.phase == .idle else { return }
                self.place(on: ScreenChooser.home())
                if let pending = self.pendingProjects { self.pendingProjects = nil; self.install(pending) } else { self.push() }
                self.refreshProjects()
            }
            timer?.cancel(); stopKeys(); panel.allowsKey = false; panel.ignoresMouseEvents = true
        case .open:
            startKeys(); panel.allowsKey = true; panel.ignoresMouseEvents = false; if !openedByHover { panel.makeKey() }
            restartTimer()
        case .switcher:
            timer?.cancel()
            startKeys(); panel.allowsKey = true; panel.ignoresMouseEvents = false; if !openedByHover { panel.makeKey() }
        case .setup:
            startKeys(); panel.allowsKey = true; panel.ignoresMouseEvents = false; if !openedByHover { panel.makeKey() }
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
        guard machine.autoCollapses, !holdOpen else { return }
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
        case "snooze": snooze()
        case "switcher": send(.openSwitcher)
        case "openSettings": NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")!)
        case "choose": if let i = body["index"] as? Int { send(.choose(i)) }
        case "size":
            if let w = body["width"] as? Double, let h = body["height"] as? Double { contentSize = CGSize(width: w, height: h) }
        case "log": NSLog("Perch UI: \(body["text"] ?? "")")
        default: break
        }
    }

    /// "Not now": hide the card and bring it back later, unless you come back to it yourself first.
    private func snooze() {
        send(.dismiss)
        snoozeTask?.cancel()
        snoozeTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(self.snoozeSeconds))
            if !Task.isCancelled, self.machine.phase == .idle { self.comeBack() }
        }
    }

    // MARK: keys
    private func startKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, self.machine.phase != .idle else { return e }
            switch e.keyCode {
            case 36, 76: self.send(.confirm)
            case 53: self.send(.dismiss)
            case 48: if self.machine.phase == .open { self.send(.openSwitcher) } else { self.send(e.modifierFlags.contains(.shift) ? .previous : .next) }
            case 45: if self.machine.phase == .open { self.snooze() } else { return e }
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
        guard machine.phase != .idle else { return }
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
        if machine.phase == .idle { hoverIdle(); return }
        let rect = NotchGeometry.contentRect(width: contentSize.width, height: contentSize.height, screen: info)
        let inside = rect.contains(NSEvent.mouseLocation)
        panel.ignoresMouseEvents = !inside
        if inside, panel.allowsKey, !panel.isKeyWindow { panel.makeKey() }
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
