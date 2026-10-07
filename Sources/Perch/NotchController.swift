import AppKit
import WebKit
import PerchCore

/// Owns the state machine, the transparent panel, and the web view that draws the card.
@MainActor
final class NotchController: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private let panel = NotchPanel()
    private let web: WKWebView
    private var machine: NotchMachine
    private let projects: [Project]
    private var screen: NSScreen
    private var info: ScreenInfo
    private var contentSize = CGSize(width: NotchGeometry.cardWidth, height: 160)
    private var timerToken = 0
    private var timer: Task<Void, Never>?
    private var keyMonitor: Any?
    private var mouseMonitors: [Any] = []
    private var ready = false

    init(provider: SessionProviding) {
        projects = provider.parkedProjects()
        machine = NotchMachine(projectCount: projects.count)
        screen = ScreenChooser.current()
        info = screen.screenInfo

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
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { guard let self, self.machine.phase == .idle else { return }; self.place(on: ScreenChooser.current()); self.push() }
        }
    }

    // MARK: public actions
    func comeBack() { prepareToShow(); send(.comeBack) }
    func toggleSwitcher() { prepareToShow(); send(.openSwitcher) }
    func confirm() { send(.confirm) }

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
    private func prepareToShow() { if machine.phase == .idle { place(on: ScreenChooser.current()) } }

    private func place(on s: NSScreen) {
        screen = s; info = s.screenInfo
        panel.setFrame(NotchGeometry.panelFrame(for: info), display: true)
    }

    func send(_ event: NotchEvent) {
        let old = machine.phase
        machine.send(event)
        if machine.phase != old { phaseChanged(old, machine.phase) }
        push()
    }

    private func push() {
        guard ready else { return }
        let snap = UISnapshot(machine: machine, projects: projects, screen: info, timerToken: timerToken)
        guard let data = try? JSONEncoder().encode(snap), let json = String(data: data, encoding: .utf8) else { return }
        web.evaluateJavaScript("window.perch && window.perch.apply(\(json))", completionHandler: nil)
    }

    private func phaseChanged(_ old: NotchPhase, _ new: NotchPhase) {
        switch new {
        case .idle:
            timer?.cancel(); stopKeys(); panel.allowsKey = false; panel.ignoresMouseEvents = true
        case .open:
            if old == .idle { haptic(.alignment) }
            startKeys(); panel.allowsKey = true; panel.ignoresMouseEvents = false; panel.makeKey()
            restartTimer()
        case .switcher:
            if old == .idle { haptic(.alignment) }
            timer?.cancel()
            startKeys(); panel.allowsKey = true; panel.ignoresMouseEvents = false; panel.makeKey()
        case .restoring:
            timer?.cancel(); haptic(.levelChange)
            timer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(3.2))
                if !Task.isCancelled { self?.send(.restoreFinished) }
            }
        }
    }

    private func haptic(_ p: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(p, performanceTime: .now)
    }

    private func restartTimer() {
        timer?.cancel(); timerToken += 1
        guard machine.autoCollapses else { return }
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
        case "choose": if let i = body["index"] as? Int { send(.choose(i)) }
        case "size":
            if let w = body["width"] as? Double, let h = body["height"] as? Double { contentSize = CGSize(width: w, height: h) }
        case "log": NSLog("Perch UI: \(body["text"] ?? "")")
        default: break
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
            case 48: self.send(e.modifierFlags.contains(.shift) ? .previous : .next)
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
    private func installMouseMonitors() {
        let handler: (NSEvent?) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.mouseMoved() } }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: handler) { mouseMonitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { e in handler(e); return e }) { mouseMonitors.append(l) }
    }
    private func mouseMoved() {
        guard machine.phase != .idle else { return }
        let rect = NotchGeometry.contentRect(width: contentSize.width, height: contentSize.height, screen: info)
        let inside = rect.contains(NSEvent.mouseLocation)
        panel.ignoresMouseEvents = !inside
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
