import AppKit
import WebKit
import ServiceManagement
import PerchCore

/// Owns the state machine, the transparent panel, and the web view that draws the card.
@MainActor
final class NotchController: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private let panel = NotchPanel()
    private let web: CardWebView
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
    /// What you typed in the list to narrow it. Cleared when the card closes.
    private var listQuery = ""
    /// The app icons this page has. Nil until sent, and again after the page reloads.
    private var iconKeys: Set<String>?
    private var iconsCheckedAt = Date.distantPast
    private var activity: NSObjectProtocol?
    private var snoozeTask: Task<Void, Never>?
    private var hoverTask: Task<Void, Never>?
    /// The cursor is on the tab or notch, so it leans toward you.
    private var tabHot = false
    /// The pointer is on something to click, the page says (from what it marks under the pointer). WebKit shows the hand
    /// itself only on a card with the keyboard; a card without it hears no pointer moves, so Perch shows it.
    private var handCursor = false
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
    /// What you have typed in each session's reply and not sent, by project id. Kept while Perch runs, not on disk: closing
    /// the card (a click in Finder to copy a path) keeps it, and the reply field opens with it again.
    private var drafts: [String: String] = [:]
    /// What showed when the card or list was put away, for Command+Option to bring back (PutAway).
    private var putAway: PutAway?
    /// The card takes the keyboard when the pointer comes onto it, or when a hovered card gets something to answer:
    /// once, never again while things stay that way. An app that takes the keyboard after that (Raycast, Spotlight)
    /// keeps it, or Perch would snatch it back within a frame and close it.
    private var pointerOnCard = false
    private var tookKeysForAsk = false
    private var askedForAccessibility = false
    /// A reply typed before Perch had Accessibility, held until it is on (Allow and send).
    private var waitingReply: (id: String, text: String)?
    private var waitingTask: Task<Void, Never>?
    /// After a card closes, hovering won't reopen it until the cursor has left the notch once.
    private var hoverLatched = false
    /// Simulation mode: the welcome card stays until you act on it.
    var holdOpen = false
    /// How long "Not now" hides the card before it comes back.
    var snoozeSeconds: Double = 30 * 60
    /// "Not now" holds until then: coming back from a break does not override it.
    private var snoozedUntil = Date.distantPast
    /// When you last saw each session's latest activity, by session id.
    private var seen = Prefs.seen
    /// When Perch last switched Claude's window to a session behind your back to send a reply, by the app's session id.
    private var shownQuietly: [String: Date] = [:]
    /// The project on the welcome card right now, and since when. A second on screen counts as seen.
    private var viewing: (id: String, since: Date)?
    /// Your last break: when you left and when you came back.
    private var lastAway: (since: Date, back: Date)?
    /// A proactive card held back by a call; it shows when the call is over.
    private var held: (reminder: Bool, until: Date)?
    private var heldTask: Task<Void, Never>?
    /// The first scan has finished, so an empty list really is empty.
    private var scannedOnce = false
    /// You asked for the card before the first scan finished: the list shows "Looking" and turns into the card when it can.
    private var openWhenScanned = false
    /// What the hooks said about each session, by session id. It beats the transcript's guess.
    private let hookServer = HookServer()
    private var live: [String: LiveStatus] = [:]
    /// The scan as it came, before live status, model words and ordering.
    private var base: [Project] = []

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
        web = CardWebView(frame: .zero, configuration: config)
        super.init()
        // A card that offers Reply: one asking you something has no field to drop into.
        web.takesFiles = { [weak self] in
            guard let self, self.machine.phase == .open, self.projects.indices.contains(self.machine.selected) else { return false }
            return self.projects[self.machine.selected].ask == nil
        }
        web.onDrag = { [weak self] n, at in
            self?.web.evaluateJavaScript("window.perch && window.perch.dragOver(\(n), \(at.x), \(at.y))", completionHandler: nil)
        }
        web.onFiles = { [weak self] paths in
            guard let self, self.machine.phase == .open else { return false }
            // Dropped on the card: it takes the keyboard, as a click on it would, so you can type around the path.
            self.addPaths(paths); self.panel.makeKey(); return true
        }
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
        Self.setsCursorInBackground()
        hookServer.onEvent = { [weak self] e in self?.hookEvent(e) }
        hookServer.onAbandoned = { [weak self] id in self?.askWentAway(id) }
        hookServer.start()
        startRefreshing()
        startWatchingFocus()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { guard let self, self.machine.phase == .idle else { return }; self.place(on: ScreenChooser.current()); self.push() }
        }
    }

    // MARK: public actions
    /// `proactive` is Perch speaking up on its own (you came back from being away, a snooze ended). Then it never
    /// talks about the session you are already in: that one goes to the back, and if it is the only one, nothing shows.
    /// `reminder` is a "Not now" coming due; it is the one proactive open a snooze allows.
    /// `awaySince` is when you left, for "Finished 12m after you left".
    func comeBack(byHover: Bool = false, proactive: Bool = false, reminder: Bool = false, awaySince: Date? = nil) {
        guard machine.phase == .idle else { return }
        // Resting on the notch soon after you put away a reply you were writing brings that back, words and all.
        if byHover, putAway?.replying == true, reopen(byHover: true) { return }
        if let since = awaySince { lastAway = (since, Date()) }
        if proactive && !reminder && Date() < snoozedUntil { return }
        // On a call, on camera or presenting: hold the card until that is over.
        if proactive, let why = Quiet.reason() { holdUntilQuiet(reminder: reminder, why: why); return }
        if !proactive && !byHover {
            // You asked for it yourself, so the snooze is over. With nothing to show yet, the list says so instead of doing nothing.
            snoozeTask?.cancel(); snoozedUntil = .distantPast; held = nil
            if projects.isEmpty { openWhenScanned = !scannedOnce; toggleSwitcher(); return }
        }
        if proactive {
            let active = youAreIn().maybe
            if reminder {
                guard projects.contains(where: { !active.contains($0.id) }) else { return }
            } else {
                // Speak up only when something happened since you last looked: a session finished, asked you something or stopped.
                let news = projects.filter { !active.contains($0.id) && isNews($0) }.sorted { ($0.lastActive ?? .distantPast) > ($1.lastActive ?? .distantPast) }
                guard !news.isEmpty else { return }
                let first = Set(news.map(\.id))
                projects = news + projects.filter { !first.contains($0.id) }
            }
            projects = projects.filter { !active.contains($0.id) } + projects.filter { active.contains($0.id) }
        }
        openedByHover = byHover; proactiveOpen = proactive; openedAt = Date(); leftCardAt = nil; prepareToShow(); send(.comeBack)
        refreshProjects()   // the card shows what we have now and updates itself a moment later
    }

    // MARK: the live activity
    /// What the notch shows beside the camera when an answer or a request arrives (app.js activity): "", "wings" or "full".
    private var activityMode = ""
    private var activitySize = CGSize.zero
    /// Registers the Command+Option keys its buttons answer to, and drops them when it goes.
    var onActivityKeys: (([String]) -> Void)?
    func playActivityDemo() { web.evaluateJavaScript("window.perch && window.perch.actDemo()", completionHandler: nil) }
    func activityKey(_ name: String) { web.evaluateJavaScript("window.perch && window.perch.actKey('\(name)')", completionHandler: nil) }

    /// The notch grown for the activity, in screen coordinates.
    private var activityRect: CGRect {
        CGRect(x: info.frame.midX - activitySize.width / 2, y: info.frame.maxY - activitySize.height, width: activitySize.width, height: activitySize.height)
    }

    /// Opens that session's card as if you asked for it, with the keyboard, so A, D and Esc answer it; Reply opens its field.
    private func openCard(for id: String, reply: Bool) {
        guard machine.phase == .idle, let i = projects.firstIndex(where: { $0.id == id }) else { return }
        projects.insert(projects.remove(at: i), at: 0)
        comeBack()
        if reply { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.web.evaluateJavaScript("window.perch && window.perch.replyMenu(true)", completionHandler: nil) } }
    }

    /// Calls and presentations, checked at most every few seconds: push() runs often.
    private var quietChecked: (at: Date, on: Bool) = (.distantPast, false)
    private func quietNow() -> Bool {
        if Date().timeIntervalSince(quietChecked.at) > 5 { quietChecked = (Date(), Quiet.reason() != nil) }
        return quietChecked.on
    }

    /// The session you are in (`sure`) and the ones you may be in (`maybe`, which includes `sure`). In a terminal that is the
    /// agent in the focused cmux surface, herdr pane or Terminal/iTerm2 tab; in the Claude app, the session its window shows.
    /// Where Perch cannot tell (an app it cannot read, a reading gone stale, the Codex app), every live session in that app
    /// is a maybe: it would rather stay quiet about one of them than nudge you about the one you are looking at.
    private func youAreIn() -> (sure: Set<String>, maybe: Set<String>) {
        guard let bid = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return ([], []) }
        if FocusProbe.reads(bid), focus.fresh(for: bid) == nil, hasSessions(in: bid) { focus.poll(app: bid) }
        switch bid {
        case Restorer.claudeApp:
            var id: String?
            switch focus.fresh(for: bid)?.claude {
            case .session(let shown)?: id = shown
            case .some(.none): id = nil   // its window shows no session
            default:
                // Not readable: the app's own record of the session it had in front last (it can lag behind a switch).
                id = DesktopSessions.shared.index().values.compactMap { e in e.focusedAt.map { (e.id, $0) } }.max { $0.1 < $1.1 }?.0
            }
            let hit = Set(projects.filter { $0.desktopSessionId != nil && $0.desktopSessionId == id }.map(\.id))
            if ProcessInfo.processInfo.environment["PERCH_TRACE"] != nil {
                let line = "claude app shows \(String(describing: focus.fresh(for: bid)?.claude)) -> \(id ?? "none") in=\(hit.sorted())"
                if line != traced { traced = line; NSLog("Perch in: \(line)") }
            }
            return (hit, hit)
        case Restorer.codexApp: return ([], Focus.inCodexApp(projects))
        default:
            guard Terminals.keys[bid] != nil else { return ([], []) }
            let r = Focus.inTerminal(projects, app: bid == "com.cmuxterm.app.nightly" ? Terminals.cmux : bid, looking: focus.fresh(for: bid)?.looking ?? .cannotTell)
            traceFocus(bid, r)
            return r
        }
    }
    private let focus = FocusProbe()
    /// Whether there is anything in that app to tell apart: nothing is read for an app that has no session of ours.
    private func hasSessions(in bid: String) -> Bool {
        if bid == Restorer.claudeApp { return projects.contains { $0.desktopSessionId != nil } }
        let app = bid == "com.cmuxterm.app.nightly" ? Terminals.cmux : bid
        return projects.contains { $0.terminal && $0.via == app && $0.spot != nil }
    }
    private var traced = ""
    private func traceFocus(_ bid: String, _ r: (sure: Set<String>, maybe: Set<String>)) {
        guard ProcessInfo.processInfo.environment["PERCH_TRACE"] != nil else { return }
        let line = "\(bid) looking \(focus.fresh(for: bid)?.looking.spots.sorted() ?? []) unknown=\(focus.fresh(for: bid)?.looking.unknown ?? true) sure=\(r.sure.sorted()) maybe=\(r.maybe.sorted()) live=\(projects.compactMap { p in p.spot.map { "\(p.sessionId?.prefix(8) ?? "?") \($0.suffix(12))" } })"
        if line != traced { traced = line; NSLog("Perch in: \(line)") }
    }
    /// A second apart while the app in front is one Perch can read, so a switch is seen before anything arrives.
    private func startWatchingFocus() {
        focus.changed = { [weak self] in if self?.machine.phase == .idle { self?.push() } }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                // Also while a card is up: a reading that went stale there would make every session in the app a maybe the moment it closes.
                guard let self, let bid = NSWorkspace.shared.frontmostApplication?.bundleIdentifier, FocusProbe.reads(bid), self.hasSessions(in: bid) else { return }
                self.focus.tick(app: bid)
            }
        }
        RunLoop.main.add(t, forMode: .common)
    }
    /// Command+Option tapped: close whatever is showing, or bring back what you put away a moment ago, else open the list.
    func chordTap() {
        guard machine.phase == .idle else { send(.dismiss); return }
        if !reopen() { toggleSwitcher() }
    }

    /// The card or list you put away in the last few minutes, as you left it: the same session's card, or the list with
    /// what you typed on the same row, and a reply that was open with its words. False when there is nothing to bring back.
    private func reopen(byHover: Bool = false) -> Bool {
        guard let away = putAway else { return false }
        guard let event = away.recall(ids: projects.map(\.id), now: Date()) else { putAway = nil; return false }
        openedByHover = byHover; proactiveOpen = false; openedAt = Date(); leftCardAt = nil; prepareToShow()
        if away.phase == .switcher { listQuery = away.query }
        send(event)
        guard machine.phase != .idle else { return false }
        if machine.phase == .switcher, case .reopen(_, nil) = event { filterChanged() }   // its row has gone: the top one that matches
        if away.replying { web.evaluateJavaScript("window.perch && window.perch.replyMenu(true)", completionHandler: nil) }
        refreshProjects()
        return true
    }
    func toggleSwitcher() {
        let fromIdle = machine.phase == .idle
        openedByHover = false; proactiveOpen = false; prepareToShow()
        send(.openSwitcher)
        // Opened by itself, the list starts on its top row: what needs you, or what you touched last. (Closed, the machine
        // keeps no selection, so this comes once it is open.)
        if fromIdle, machine.phase == .switcher, let top = ListFilter.ordered(projects, "", now: Date()).first {
            machine.send(.projectsChanged(count: projects.count, selected: top)); push()
        }
        refreshProjects()
    }
    func confirm() { send(.confirm) }

    /// The desktop behind snapshots: a wallpaper (Raycast's, for the README) seen from the top of the screen.
    var snapshotWallpaper: NSImage?

    /// Debug: write the web view's current pixels to a PNG, over the wallpaper as the top of this screen shows it.
    /// `top`: keep only that much of the panel from its top edge, in points (the live activity is a strip, not a card).
    func snapshot(to path: String, top: CGFloat? = nil) {
        let cfg = WKSnapshotConfiguration(); cfg.snapshotWidth = NSNumber(value: Double(web.bounds.width) * 2)
        let screen = info.frame.size, panel = NotchGeometry.panelSize, wall = snapshotWallpaper
        web.evaluateJavaScript("window.perch && window.perch.still && window.perch.still()", completionHandler: nil)
        web.takeSnapshot(with: cfg) { image, _ in
            guard let image else { return }
            let size = image.size
            let out = NSImage(size: size)
            out.lockFocus()
            if let wall, wall.size.width > 0 {
                // Scale the wallpaper to fill the screen and take the strip under the panel, centred, a little way down
                // where the colour is: the very top of most wallpapers is dark, and the card is black.
                let k = max(screen.width / wall.size.width, screen.height / wall.size.height)
                let x = ((wall.size.width * k - screen.width) / 2 + (screen.width - panel.width) / 2) / k
                let h = (panel.height + NotchGeometry.overscan) / k
                let top = wall.size.height * 0.2
                wall.draw(in: NSRect(origin: .zero, size: size), from: NSRect(x: x, y: wall.size.height - top - h, width: panel.width / k, height: h), operation: .copy, fraction: 1)
            } else {
                NSColor(calibratedRed: 0.13, green: 0.19, blue: 0.18, alpha: 1).setFill()
                NSRect(origin: .zero, size: size).fill()
            }
            image.draw(in: NSRect(origin: .zero, size: size))
            out.unlockFocus()
            guard let tiff = out.tiffRepresentation, var rep = NSBitmapImageRep(data: tiff) else { return }
            if let top, let cg = rep.cgImage {
                let px = Int(top / (panel.height + NotchGeometry.overscan) * CGFloat(cg.height))
                if let cut = cg.cropping(to: CGRect(x: 0, y: 0, width: cg.width, height: min(px, cg.height))) { rep = NSBitmapImageRep(cgImage: cut) }
            }
            if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: path)) }
        }
    }

    // MARK: state
    /// The card opens on the display the cursor is on, the same one whose notch or tab you hovered.
    private func prepareToShow() {
        guard machine.phase == .idle else { return }
        place(on: ScreenChooser.current())
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
                self.refreshing = false; self.scannedOnce = true
                switch self.machine.phase {
                case .idle: self.install(list)
                case .open, .switcher: self.installLive(list)
                case .onboarding, .settings: self.base = list; self.projects = self.decorate(list); self.machine.send(.projectsChanged(count: self.projects.count, selected: 0)); self.push()
                default: self.pendingProjects = list
                }
                if self.openWhenScanned {
                    self.openWhenScanned = false
                    if self.machine.phase == .switcher, !list.isEmpty { self.send(.back) } else { self.push() }
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
        // The Claude app's own session records too: switching sessions there rewrites lastFocusedAt, which decides the session
        // you are in (and so what the notch keeps quiet about).
        let paths = [".claude/projects", ".codex/sessions", "Library/Application Support/Claude/claude-code-sessions", ".local/share/opencode", ".pi/agent/sessions"]
            .map { home.appendingPathComponent($0).path }.filter { FileManager.default.fileExists(atPath: $0) }
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
    // MARK: what you have seen
    private func isFresh(_ p: Project) -> Bool {
        guard let t = p.lastActive, t > newsSince else { return false }
        // Already in front of you in the Claude app since it changed: you have seen it there. Not when Perch put it there
        // itself to send a reply, with the window behind.
        if let f = p.focusedAt, f.addingTimeInterval(10) >= t,
           !(p.desktopSessionId.flatMap { shownQuietly[$0] }.map { abs(f.timeIntervalSince($0)) < 5 } ?? false) { return false }
        return t.timeIntervalSince1970 > (seen[p.id] ?? 0) + 0.5
    }
    /// Since your last break, or the last day: anything older is history, seen or not.
    private var newsSince: Date { WhileAway.newsSince(now: Date(), lastLeft: lastAway?.since) }
    /// News: changed since you last looked and not still working.
    private func isNews(_ p: Project) -> Bool { isFresh(p) && p.status.kind != "running" }

    private func markSeen(_ p: Project) {
        guard let t = p.lastActive?.timeIntervalSince1970, (seen[p.id] ?? 0) < t else { return }
        seen[p.id] = t
        if seen.count > 300 { seen = Dictionary(uniqueKeysWithValues: seen.sorted { $0.value > $1.value }.prefix(200).map { ($0.key, $0.value) }) }
        Prefs.seen = seen
    }

    /// Sessions from before Perch was installed are not news. The session you are in counts as seen while you are at the Mac.
    private func noteSeen() {
        if !Prefs.seenBaselined { projects.forEach(markSeen); Prefs.seenBaselined = true }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        if idle < 60 { let here = youAreIn().sure; projects.filter { here.contains($0.id) }.forEach(markSeen) }
    }

    /// Called on every redraw: a project that stayed on the welcome card for a second has been seen.
    private func trackViewing() {
        let current = machine.phase == .open && projects.indices.contains(machine.selected) ? projects[machine.selected].id : nil
        guard viewing?.id != current else { return }
        if let v = viewing, Date().timeIntervalSince(v.since) >= 1, let p = projects.first(where: { $0.id == v.id }) { markSeen(p) }
        viewing = current.map { ($0, Date()) }
    }

    /// The break the card is about, while you are just back from it.
    private var awaySinceForCard: Date? {
        guard let a = lastAway, Date().timeIntervalSince(a.back) < 15 * 60 else { return nil }
        return a.since
    }

    private func holdUntilQuiet(reminder: Bool, why: String) {
        NSLog("Perch: holding the welcome card, \(why)")
        held = (reminder || (held?.reminder ?? false), Date().addingTimeInterval(3 * 3600))
        guard heldTask == nil else { return }
        heldTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, let h = self.held else { break }
                if Date() > h.until { self.held = nil; break }
                guard self.machine.phase == .idle, Quiet.reason() == nil else { continue }
                // The call is over and you are here: a good moment. It counts as coming back now.
                self.held = nil; self.heldTask = nil
                if let a = self.lastAway { self.lastAway = (a.since, Date()) }
                self.comeBack(proactive: true, reminder: h.reminder)
                return
            }
            self?.heldTask = nil
        }
    }

    private func installLive(_ list: [Project]) {
        base = list
        // While you look at the card or the list, rows keep their places; new ones join at the end.
        let place = Dictionary(projects.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        let next = decorate(list).enumerated().sorted { (place[$0.element.id] ?? 1000 + $0.offset) < (place[$1.element.id] ?? 1000 + $1.offset) }.map(\.element)
        guard next != projects else { return }
        let keep = projects.indices.contains(machine.selected) ? projects[machine.selected].id : nil
        projects = next
        machine.send(.projectsChanged(count: next.count, selected: next.firstIndex { $0.id == keep } ?? 0))
        noteSeen()
        push()
    }

    private func install(_ list: [Project]) {
        base = list
        projects = decorate(list)
        machine.projectCount = projects.count
        noteSeen()
        push()
    }

    /// Live hook status over the transcript's guess, then what needs you first.
    private func decorate(_ list: [Project]) -> [Project] {
        let withLive = list.map { p -> Project in
            guard let l = live[p.sessionId ?? p.id], l.holds(for: p) else { return p }
            return p.applying(l)
        }
        let since = newsSince
        return urgent(withLive.map { $0.settled(since: since) })
    }

    /// Asking you first, then what finished since you looked, then what is working, then the rest; newest first in each.
    private func urgent(_ list: [Project]) -> [Project] {
        func rank(_ p: Project) -> Int {
            switch p.status.kind { case "attention": 0; case "running": 2; case "done": isNews(p) ? 1 : 3; default: 3 }
        }
        return list.enumerated().sorted { a, b in
            let ra = rank(a.element), rb = rank(b.element)
            if ra != rb { return ra < rb }
            return (a.element.lastActive ?? .distantPast, -a.offset) > (b.element.lastActive ?? .distantPast, -b.offset)
        }.map(\.element)
    }

    /// The hooks changed something: redraw from the same scan.
    private func redecorate() {
        if machine.phase == .open || machine.phase == .switcher { installLive(base) }
        else { projects = decorate(base); machine.send(.projectsChanged(count: projects.count, selected: 0)); push() }
    }

    // MARK: hooks
    private func hookEvent(_ e: HookEvent) {
        let before = live[e.sessionId]
        let now = LiveStatus.apply(e, to: before)
        // Requests this event settled (answered in the app, or the turn moved on) let their hooks go.
        for a in before?.asks ?? [] where !now.asks.contains(where: { $0.id == a.id }) { hookServer.release(a.id) }
        live[e.sessionId] = now
        if live.count > 120 { live = Dictionary(uniqueKeysWithValues: live.sorted { $0.value.at > $1.value.at }.prefix(80).map { ($0.key, $0.value) }) }
        if ProcessInfo.processInfo.environment["PERCH_TRACE"] != nil { NSLog("Perch hook: \(e.agent) \(e.sessionId.prefix(8)) \(e.kind)") }
        // A session Perch has not listed yet may be new: look again, but not on every tool call of a session it skips on purpose.
        if !base.contains(where: { ($0.sessionId ?? $0.id) == e.sessionId }) {
            if case .toolRan = e.kind {} else { sessionFilesChanged() }
            return
        }
        redecorate()
    }

    private func askWentAway(_ id: String) {
        for (sid, var l) in live where l.asks.contains(where: { $0.id == id }) { l.settle(id, at: Date()); live[sid] = l }
        redecorate()
    }

    /// Allow, deny, or one of a question's options, for the request on the card. The card closes; the agent goes on.
    private func answer(_ choice: String, answers: [String: String]? = nil, at index: Int? = nil) {
        let i = index ?? machine.selected
        guard projects.indices.contains(i), let ask = projects[i].ask, ask.answerable else { return }
        let p = projects[i]
        hookServer.answer(ask.id, with: answers.map { ask.reply(answers: $0) } ?? ask.reply(choice))
        if let sid = p.sessionId { live[sid]?.settle(ask.id, at: Date()) }
        markSeen(p)
        let onCard = machine.phase != .idle
        send(.dismiss)
        if onCard || putAway?.session == p.id { putAway = nil }   // answered: nothing to bring back
        redecorate()
    }

    private func startRefreshing() {
        // Switching apps changes which session counts as "the one you are in", so the resting character is re-evaluated.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                // Pick up opens a closed terminal session in the terminal you use.
                if let bid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier {
                    if Terminals.keys[bid] != nil { Prefs.lastTerminal = bid }
                    if FocusProbe.reads(bid), self?.hasSessions(in: bid) == true { self?.focus.poll(app: bid) }
                }
                if self?.machine.phase == .idle { self?.push() }
            }
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

    private func pickUp(_ index: Int, then done: @escaping @MainActor (Landing) -> Void = { _ in }) {
        guard projects.indices.contains(index) else { return }
        markSeen(projects[index])
        Restorer.resume(projects[index], then: done)
        let old = machine.phase
        machine.send(.dismiss)
        phaseChanged(old, machine.phase)
        // You went there: nothing to bring back. From the live activity, only if it was the card you put away.
        if old != .idle || putAway?.session == projects[index].id { putAway = nil }
        push()
    }

    private func push() {
        trackViewing()
        guard ready else { return }
        let away = awaySinceForCard, now = Date()
        let fresh = Set(projects.filter(isFresh).map(\.id))
        let lines = Dictionary(projects.map { p in (p.id, WhileAway.line(kind: p.status.kind, lastActive: p.lastActive, now: now, awaySince: away, fresh: fresh.contains(p.id))) }, uniquingKeysWith: { a, _ in a })
        let snap = UISnapshot(machine: machine, projects: projects, screen: info, timerToken: timerToken, icons: iconsToSend(), allowAutoCollapse: proactiveOpen && !holdOpen && !openedByHover && !snoozeMenuOpen && !replyOpen,
                          activeId: nil, activeIds: machine.phase == .idle ? youAreIn().maybe.sorted() : [],
                          scanning: !scannedOnce, canSend: AXIsProcessTrusted(), fresh: fresh, lines: lines,
                          onboarding: machine.phase == .onboarding ? onboardingState() : nil,
                          settings: machine.phase == .settings ? settingsState() : nil)
        var sent = snap
        // The list draws its rows in this order, by section; with something typed, only the ones that match.
        if machine.phase == .switcher { sent.query = listQuery; sent.shown = ListFilter.ordered(projects, listQuery, now: Date()) }
        if machine.phase == .idle { sent.quiet = quietNow() }
        sent.allowing = waitingReply != nil
        sent.drafts = drafts
        sent.proactive = proactiveOpen
        let askTakesKeys = machine.phase == .open && openedByHover && cardTakesKeys
        if askTakesKeys, !tookKeysForAsk, panel.allowsKey, !panel.isKeyWindow { panel.makeKey() }
        tookKeysForAsk = askTakesKeys
        guard let data = try? JSONEncoder().encode(sent), let json = String(data: data, encoding: .utf8) else { return }
        web.evaluateJavaScript("window.perch && window.perch.apply(\(json))", completionHandler: nil)
    }

    /// Icons go once per page load. An app missing from them (installed later, or mid-update at launch) is looked for again each minute.
    private func iconsToSend() -> [String: String]? {
        if let keys = iconKeys {
            guard projects.contains(where: { !keys.contains($0.app) && AppIcons.knows($0.app) }), Date().timeIntervalSince(iconsCheckedAt) > 60 else { return nil }
        }
        iconsCheckedAt = Date()
        let icons = AppIcons.all()
        if let keys = iconKeys, Set(icons.keys) == keys { return nil }
        iconKeys = Set(icons.keys)
        return icons
    }

    private func phaseChanged(_ old: NotchPhase, _ new: NotchPhase) {
        if old == .onboarding { Prefs.onboarded = true; onbTask?.cancel() }
        if ProcessInfo.processInfo.environment["PERCH_TRACE"] != nil {
            NSLog("Perch phase: \(old) -> \(new)")
            if new == .idle { NSLog("Perch closed by: \(Thread.callStackSymbols.dropFirst(2).prefix(4).joined(separator: " | "))") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in NSLog("Perch key window: \(self?.panel.isKeyWindow ?? false), front app: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "-")") }
        }
        switch new {
        case .idle:
            if old == .open || old == .switcher {
                putAway = PutAway(phase: old, session: projects.indices.contains(machine.selected) ? projects[machine.selected].id : nil,
                                  query: listQuery, replying: replyOpen, at: Date())
            }
            hoverLatched = true; snoozeMenuOpen = false; replyOpen = false; listQuery = ""; pointerOnCard = false
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(700))
                guard let self, self.machine.phase == .idle else { return }
                self.place(on: ScreenChooser.current())
                if let pending = self.pendingProjects { self.pendingProjects = nil; self.install(pending) } else { self.push() }
                self.refreshProjects()
            }
            timer?.cancel(); stopKeys(); panel.allowsKey = false; panel.ignoresMouseEvents = true
            // The card had the keyboard: hand it back to the app you were in. A key window stays key after it can no
            // longer become key, and the panel never leaves the screen, so step out and back in.
            if panel.isKeyWindow { panel.orderOut(nil); panel.orderFrontRegardless() }
        case .open:
            startKeys(); panel.allowsKey = true; panel.ignoresMouseEvents = false; if cardTakesKeys { panel.makeKey() }
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
        case .restoring:
            timer?.cancel()
            timer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(3.2))
                if !Task.isCancelled { self?.send(.restoreFinished) }
            }
        }
    }


    private func restartTimer() {
        timer?.cancel(); timerToken += 1
        // Only a card Perch opened on its own counts down. One you asked for stays until you are done with it.
        guard machine.autoCollapses, proactiveOpen, !holdOpen, !openedByHover, !snoozeMenuOpen, !replyOpen else { return }
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(9))
            if !Task.isCancelled { self?.send(.timeout) }
        }
    }

    // MARK: web view
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { ready = true; iconKeys = nil; push() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) { NSLog("Perch: web load failed: \(error)") }

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "confirm": send(.confirm)
        case "flip": send(.next)
        case "answer":
            if let a = body["answers"] as? [String: String] { answer("", answers: a) }
            else if let c = body["choice"] as? String { answer(c) }
        case "details": if let i = body["index"] as? Int { send(.show(i)) }
        case "hooks":
            let on = body["on"] as? Bool ?? true
            for agent in HookInstaller.agents where (Prefs.enabledSources.contains(agent) && (["claude", "codex"].contains(agent) || AgentPresence.installed(.of(agent)))) || !on {
                do { if on { try HookInstaller.install(agent) } else { try HookInstaller.uninstall(agent) } }
                catch { NSLog("Perch: hooks for \(agent): \(error.localizedDescription)") }
            }
            push()
        case "dismiss": send(.dismiss)
        case "snooze": snooze(body["when"] as? String ?? "30m")
        case "replyMenu":
            replyOpen = body["open"] as? Bool ?? false
            if replyOpen { timer?.cancel(); panel.makeKey() } else { restartTimer(); cancelWaiting() }
            push()
        case "reply": if let t = body["text"] as? String { reply(t, closeAfter: body["close"] as? Double ?? 0.78) }
        case "draft": if let id = body["id"] as? String { drafts[id] = (body["text"] as? String).flatMap { $0.isEmpty ? nil : $0 } }
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
            if body["only"] as? Bool == true, machine.phase == .settings {
                // Changing the character is a page inside Settings: it opens in place and Done goes back.
                onbStep = step; onbOnly = true; onbBackToSettings = true
                send(.openOnboarding)
            } else {
                send(.dismiss)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.startOnboarding(step: step) }
            }
        case "quit": NSApp.terminate(nil)
        case "menuIcon":
            if let s = body["png"] as? String, let comma = s.firstIndex(of: ","), let data = Data(base64Encoded: String(s[s.index(after: comma)...])),
               let image = NSImage(data: data) {
                image.size = NSSize(width: 18, height: 18); image.isTemplate = true
                onMenuIcon?(image)
            }
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
        case "choose": if let i = body["index"] as? Int { send(.choose(i)) }
        case "size":
            if let w = body["width"] as? Double, let h = body["height"] as? Double { contentSize = CGSize(width: w, height: h) }
        case "activity":
            activityMode = body["mode"] as? String ?? ""
            if let w = body["width"] as? Double, let h = body["height"] as? Double { activitySize = CGSize(width: w, height: h) }
            if activityMode != "full" { hoverLatched = true }   // what it folds to under the cursor is not a hover
            onActivityKeys?(body["keys"] as? [String] ?? [])
        case "activityOpen":
            if let id = body["id"] as? String { openCard(for: id, reply: body["reply"] as? Bool ?? false) }
        case "activityPick":
            if let id = body["id"] as? String, machine.phase == .idle, let i = projects.firstIndex(where: { $0.id == id }) { pickUp(i) }
        case "activityAnswer":
            if let id = body["id"] as? String, let i = projects.firstIndex(where: { $0.id == id }) {
                if let a = body["answers"] as? [String: String] { answer("", answers: a, at: i) } else if let c = body["choice"] as? String { answer(c, at: i) }
            }
        case "activitySeen":
            if let id = body["id"] as? String, let p = projects.first(where: { $0.id == id }) { markSeen(p); push() }
        case "hand":
            handCursor = body["on"] as? Bool ?? false
            if !handCursor, !panel.isKeyWindow { NSCursor.arrow.set() }
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
        send(.dismiss); putAway = nil
        snoozeTask?.cancel()
        snoozedUntil = Date().addingTimeInterval(seconds)
        snoozeTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self.snoozedUntil = .distantPast
            if self.machine.phase == .idle { self.comeBack(proactive: true, reminder: true) }
        }
    }

    /// Answers Claude or Codex without typing in its window: the exact session opens and the reply is pasted and sent.
    /// It is typed only when Perch knows the focused input belongs to that session; otherwise, and without Accessibility,
    /// the reply stays on the clipboard for you to paste. When it was typed, your clipboard is put back.
    /// `closeAfter`: when the card closes after a terminal reply, so the send animation lands first (the page says).
    /// `pid`: the session to answer, when it is not the one on the card.
    private func reply(_ text: String, to pid: String? = nil, closeAfter: Double = 0.78) {
        guard let i = projectIndex(pid) else { return }
        // A terminal session takes the words straight into its tab, and you stay where you are. A closed one opens again
        // with your words as its first message. Only a terminal Perch cannot type into falls back to pasting.
        let p = projects[i]
        drafts[p.id] = nil   // on its way; a fallback leaves it on the clipboard
        if p.terminal, let cwd = p.cwd, let id = p.sessionId {
            let agent = p.app, line = text.replacingOccurrences(of: "\n", with: " "), pid = p.pid
            let sentAt = Date(), back = WhereYouWere.now()
            markSeen(p)
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let live = LiveSessions.all()
                let hit = live.first { $0.pid == pid && $0.agent == agent } ?? live.first { $0.agent == agent && $0.argv.contains(id) }
                var done = false
                if let hit { done = Terminals.type(line, into: hit) }
                else {
                    // Not running: it opens again where it last ran, with your words as its first message.
                    _ = Restorer.reopen(agent: agent, session: id, cwd: cwd, command: Agent.of(agent).resume(id, prompt: line))
                    done = true
                    // It carries on in its new tab; you go back to what you were doing.
                    Thread.sleep(forTimeInterval: 1.5)
                    DispatchQueue.main.async { back.restore() }
                }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        guard done else { self.pasteReply(text, to: p.id); return }
                        // The words are already in the terminal; the card closes once they have flown into the notch.
                        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, closeAfter - Date().timeIntervalSince(sentAt))) {
                            guard self.machine.phase == .open else { return }
                            let old = self.machine.phase; self.machine.send(.dismiss); self.phaseChanged(old, self.machine.phase); self.putAway = nil; self.push()
                        }
                    }
                }
            }
            return
        }
        // An app session needs Accessibility: Send asks for it first and holds the words (Allow and send).
        if !AXIsProcessTrusted() { waitForAccess(text, for: p); return }
        // A session in the Claude app takes the words in the background: its window never comes forward.
        if p.app == "claude", let id = p.desktopSessionId {
            let cli = p.sessionId, topic = p.topic, back = WhereYouWere.now()
            markSeen(p)
            let old = machine.phase; machine.send(.dismiss); phaseChanged(old, machine.phase); putAway = nil; push()
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let titles = [cli.flatMap { DesktopSessions.shared.index()[$0]?.title }, topic].compactMap { $0 }
                let r = ClaudeComposer.send(text, to: id, titles: titles)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        if r.sent { self.shownQuietly[id] = Date() } else { self.pasteReply(text, to: p.id, claudeShown: r.shown, back: back, send: !r.draft) }
                    }
                }
            }
            return
        }
        pasteReply(text, to: p.id)
    }
    private func projectIndex(_ pid: String?) -> Int? {
        if let pid { return projects.firstIndex { $0.id == pid } }
        return projects.indices.contains(machine.selected) ? machine.selected : nil
    }

    /// Allow and send: asks for Accessibility the way Settings does and holds the reply until it is on, then sends it.
    /// Leaving System Settings for another app without turning it on, or two minutes going by, copies the reply and opens
    /// the session instead, as before. Esc on the card drops the wait.
    private func waitForAccess(_ text: String, for p: Project) {
        guard waitingReply == nil else { return }
        waitingReply = (p.id, text)
        onboardingAction("accessibility")   // redraws: Send now says it is waiting
        // Asking for a password or showing the system's own prompt is still part of turning it on; so is coming back to the card.
        let passing: Set<String> = ["com.apple.SecurityAgent", "com.apple.coreservices.uiagent", "com.apple.UserNotificationCenter",
                                    "com.apple.LocalAuthentication.UIAgent", Bundle.main.bundleIdentifier ?? "app.perch.mac"]
        waitingTask?.cancel()
        waitingTask = Task { [weak self] in
            let start = Date()
            var sawSettings = false
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, self.waitingReply != nil else { return }
                if AXIsProcessTrusted() { self.sendWaitingReply(); return }
                let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
                if front == "com.apple.systempreferences" { sawSettings = true; continue }
                guard (sawSettings && !passing.contains(front)) || Date().timeIntervalSince(start) > 120 else { continue }
                // The switch can take a moment to count after it is turned on.
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled, self.waitingReply != nil else { return }
                if AXIsProcessTrusted() { self.sendWaitingReply() } else { self.giveUpWaiting() }
                return
            }
        }
    }
    private func sendWaitingReply() {
        guard let w = waitingReply else { return }
        waitingReply = nil; waitingTask = nil
        if !accessibilityWas { accessibilityWas = true; onAccessibilityGranted?() }
        guard projects.contains(where: { $0.id == w.id }) else { push(); return }
        reply(w.text, to: w.id)
    }
    /// Access never came: the reply is copied and the session opens, for you to paste.
    private func giveUpWaiting() {
        guard let w = waitingReply else { return }
        waitingReply = nil; waitingTask = nil
        askedForAccessibility = true   // already asked
        drafts[w.id] = nil
        guard projects.contains(where: { $0.id == w.id }) else { push(); return }
        pasteReply(w.text, to: w.id)
    }
    private func cancelWaiting() {
        guard waitingReply != nil else { return }
        waitingReply = nil; waitingTask?.cancel(); waitingTask = nil
        push()
    }

    /// Reply by pasting: Pick up brings the session forward, then the words are pasted and sent. Needs Accessibility.
    /// Then you are put back where you were: that app and window, and in Claude the session it showed (`claudeShown`).
    /// `send` false: paste only, leaving it with your draft for you to send (a draft was in the field).
    private func pasteReply(_ text: String, to pid: String? = nil, claudeShown: String? = nil, back: WhereYouWere? = nil, send: Bool = true) {
        guard let i = projectIndex(pid) else { return }
        let back = back ?? WhereYouWere.now(), targetSession = projects[i].desktopSessionId
        let trusted = AXIsProcessTrusted()
        if !trusted, !askedForAccessibility {
            askedForAccessibility = true   // ask once per launch, never in a loop
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        }
        let pb = NSPasteboard.general
        let saved = trusted ? Clipboard.save() : nil
        pb.clearContents(); pb.setString(text, forType: .string)
        let ours = pb.changeCount
        let frontBefore = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let app = Agent.of(projects[i].app).short
        pickUp(i) { [weak self] landing in
            guard trusted else { self?.say("Reply copied"); return }
            let target: String, settle: () async -> Bool
            switch landing {
            case .app(let app, exact: true):
                // Already in front means the app navigates inside itself, which takes longer than coming forward.
                target = app; let wait = frontBefore == app ? 1.6 : 0.9
                settle = { try? await Task.sleep(for: .seconds(wait)); return true }
            case .newTerminal(let app, let cwd, let agent):
                // Type only once the agent is running, never into the shell before it.
                target = app
                settle = {
                    for _ in 0..<60 {
                        if await Task.detached(operation: { LiveSessions.all().contains { $0.cwd == cwd && $0.agent == agent } }).value {
                            try? await Task.sleep(for: .seconds(1.5)); return true
                        }
                        try? await Task.sleep(for: .milliseconds(250))
                    }
                    return false
                }
            default:
                NSLog("Perch: reply left on the clipboard (no exact session to type into)"); self?.say("Reply copied"); return
            }
            Task {
                for _ in 0..<50 {
                    if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == target { break }
                    try? await Task.sleep(for: .milliseconds(100))
                }
                guard await settle(), NSWorkspace.shared.frontmostApplication?.bundleIdentifier == target else {
                    NSLog("Perch: reply left on the clipboard (\(target) did not come forward)"); self?.say("Paste in \(app)"); return
                }
                let src = CGEventSource(stateID: .combinedSessionState)
                for down in [true, false] {
                    let e = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: down)
                    e?.flags = .maskCommand
                    e?.post(tap: .cghidEventTap)
                }
                // You wrote it and pressed Send, so it is sent: Return after the paste. Not when a draft was there: it would go too,
                // so both stay in the field for you, where you are, and nothing is put back over them.
                guard send else { NSLog("Perch: reply pasted beside a draft in \(target), not sent"); self?.say("Pasted after your draft"); return }
                try? await Task.sleep(for: .milliseconds(250))
                for down in [true, false] { CGEvent(keyboardEventSource: src, virtualKey: 36, keyDown: down)?.post(tap: .cghidEventTap) }
                NSLog("Perch: sent reply into \(target)")
                try? await Task.sleep(for: .milliseconds(600))
                if let saved, pb.changeCount == ours { Clipboard.restore(saved) }
                // Back where you were: in Claude, the session it showed; then that app and window.
                if let shown = claudeShown, shown != targetSession, let url = URL(string: "claude://code/continue?session=\(shown)") {
                    NSWorkspace.shared.open(url); try? await Task.sleep(for: .milliseconds(500))
                }
                back.restore()
            }
        }
    }

    /// Files dropped on the card or pasted from Finder: their paths go into the reply, which opens for them if it can.
    private func addPaths(_ paths: [String]) {
        guard let data = try? JSONEncoder().encode(paths), let json = String(data: data, encoding: .utf8) else { return }
        web.evaluateJavaScript("window.perch && window.perch.paths(\(json))", completionHandler: nil)
    }

    /// A word beside the notch once the card has closed, when something did not go as you would expect.
    private func say(_ text: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            let arg = (try? String(data: JSONEncoder().encode(text), encoding: .utf8)) ?? "\"\""
            self?.web.evaluateJavaScript("window.perch && window.perch.say(\(arg ?? "\"\""))", completionHandler: nil)
        }
    }

    // MARK: settings
    var onIdleMinutesChanged: ((Int) -> Void)?

    /// The agents Settings and onboarding offer: Claude and Codex always, the others once they are on this Mac.
    private func sourcesState() -> [UISnapshot.Source] {
        let counts = (provider as? RealSessionProvider)?.counts ?? [:]
        let on = Prefs.enabledSources
        return Agent.all.filter { ["claude", "codex"].contains($0.id) || (counts[$0.id]?.count ?? 0) > 0 || AgentPresence.installed($0) }.map { a in
            UISnapshot.Source(id: a.id, name: a.name, count: counts[a.id]?.count ?? 0, names: counts[a.id]?.names ?? [], enabled: on.contains(a.id))
        }
    }

    private func settingsState() -> UISnapshot.Settings {
        return UISnapshot.Settings(sources: sourcesState(), accessibility: AXIsProcessTrusted(),
                                   idleMinutes: Prefs.idleMinutes, login: SMAppService.mainApp.status == .enabled, live: liveState,
                                   back: machine.settingsFrom != nil)
    }

    /// "on" when every enabled agent on this Mac has Perch's hook installed.
    private var liveState: String {
        let on = Prefs.enabledSources.filter { id in HookInstaller.agents.contains(id) && (["claude", "codex"].contains(id) || AgentPresence.installed(.of(id))) }
        return !on.isEmpty && on.allSatisfy(HookInstaller.isInstalled) ? "on" : "off"
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        catch { NSLog("Perch: launch at login failed: \(error)") }
    }

    // MARK: onboarding
    var onAccessibilityGranted: (() -> Void)?
    /// The hello beside the notch that follows setup. For trying it out (`--hello`).
    func sayHello() { web.evaluateJavaScript("window.perch && window.perch.hi()", completionHandler: nil) }
    /// The page drew your character for the menu bar.
    var onMenuIcon: ((NSImage) -> Void)?
    private var onbStep = 0
    /// Hello, then five setup steps: look, Accessibility, apps, live status, all set.
    private let onbTotal = 6
    private var accessibilityWas = AXIsProcessTrusted()
    private var onbTask: Task<Void, Never>?
    /// Just the character step (Settings or the menu bar), not the whole setup.
    private var onbOnly = false
    /// Done and Esc return to Settings, where it was opened from.
    private var onbBackToSettings = false

    func startOnboarding(step: Int = 0, characterOnly: Bool = false) {
        guard machine.phase == .idle else { return }
        onbStep = step; onbOnly = characterOnly; onbBackToSettings = false
        snoozeTask?.cancel(); openedByHover = false; proactiveOpen = false
        place(on: ScreenChooser.current())
        if step >= 3 { refreshProjects() }
        send(.openOnboarding)
    }

    private func onboardingState() -> UISnapshot.Onboarding {
        // Scanning until the first scan is in, never again: every scan covers every agent, and the session files change
        // (and start a scan) every half second while an agent works.
        return UISnapshot.Onboarding(step: onbStep, total: onbTotal, accessibility: AXIsProcessTrusted(), scanning: !scannedOnce, sources: sourcesState(), only: onbOnly, live: liveState)
    }

    /// Leaves the character page: back to Settings when it came from there, otherwise closed.
    private func finishCharacter() {
        if onbBackToSettings { send(.openSettings) } else { send(.dismiss) }
    }

    private func onboardingAction(_ action: String) {
        switch action {
        case "next":
            if onbOnly { finishCharacter(); return }
            onbStep = min(onbStep + 1, onbTotal - 1)
            if onbStep == 3 { refreshProjects() }   // the apps step shows what the scan found
        case "back": onbStep = max(onbStep - 1, 0)
        case "finish": send(.dismiss); return
        case "accessibility":
            // A switch that is on but not working belongs to an older build of Perch (another signature). Clear Perch's own
            // entry, only when it is not working anyway, so asking adds a fresh one for this build.
            if !AXIsProcessTrusted() {
                let reset = Process(); reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
                reset.arguments = ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? "app.perch.mac"]
                try? reset.run(); reset.waitUntilExit()
            }
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
                let key = "\(trusted)|\(self.scannedOnce)|\(self.projects.count)|\(Prefs.enabledSources.sorted())|\(self.liveState)"
                if key != last { last = key; self.push() }
            }
        }
    }

    // MARK: keys
    private func startKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, self.machine.phase != .idle else { return e }
            if ProcessInfo.processInfo.environment["PERCH_TRACE"] != nil { NSLog("Perch key: \(e.keyCode) in \(self.machine.phase)") }
            if self.machine.phase == .onboarding {
                if e.charactersIgnoringModifiers?.lowercased() == "s" { self.web.evaluateJavaScript("window.perch && window.perch.onbKey('skip')", completionHandler: nil); return nil }
                switch e.keyCode {
                case 36, 76: self.web.evaluateJavaScript("window.perch && window.perch.onbKey('enter')", completionHandler: nil)
                case 123: self.web.evaluateJavaScript("window.perch && window.perch.onbKey('left')", completionHandler: nil)
                case 124: self.web.evaluateJavaScript("window.perch && window.perch.onbKey('right')", completionHandler: nil)
                case 125: self.web.evaluateJavaScript("window.perch && window.perch.onbKey('down')", completionHandler: nil)
                case 126: self.web.evaluateJavaScript("window.perch && window.perch.onbKey('up')", completionHandler: nil)
                case 53: if self.onbOnly { self.finishCharacter() } else { self.send(.dismiss) }
                default: return e
                }
                return nil
            }
            if self.machine.phase == .settings {
                // Settings works from the keyboard: arrows choose a row, Return or Space changes it, Esc is Done (or closes the
                // Apps menu first; the page decides and says "back").
                let keys: [UInt16: String] = [36: "enter", 76: "enter", 49: "enter", 123: "left", 124: "right", 125: "down", 126: "up"]
                if let k = keys[e.keyCode] { self.web.evaluateJavaScript("window.perch && window.perch.setKey('\(k)')", completionHandler: nil); return nil }
                if e.keyCode == 53 { self.web.evaluateJavaScript("window.perch && window.perch.setKey('esc')", completionHandler: nil); return nil }
                return e
            }
            if self.replyOpen {
                if e.keyCode == 53 { self.web.evaluateJavaScript("window.perch && window.perch.replyMenu(false)", completionHandler: nil); return nil }
                // Perch has no Edit menu, so nothing turns Command+V and friends into actions: send them to the field ourselves.
                let flags = e.modifierFlags.intersection([.command, .option, .control, .shift])
                let edits: [String: String] = ["v": "paste:", "c": "copy:", "x": "cut:", "a": "selectAll:", "z": flags.contains(.shift) ? "redo:" : "undo:"]
                if flags.subtracting(.shift) == .command, let action = edits[e.charactersIgnoringModifiers?.lowercased() ?? ""] {
                    // A file copied in Finder pastes as its path, not its name.
                    if action == "paste:", let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
                        self.addPaths(urls.map(\.path)); return nil
                    }
                    NSApp.sendAction(Selector((action)), to: nil, from: self); return nil
                }
                return e
            }
            // Letters by what they type, so N, R and the comma work on any keyboard layout. Digits also by position (AZERTY).
            let ch = e.charactersIgnoringModifiers?.lowercased() ?? ""
            if self.snoozeMenuOpen {
                if ch == "1" || e.keyCode == 18 { self.snooze("30m") }
                else if ch == "2" || e.keyCode == 19 { self.snooze("2h") }
                else if ch == "3" || e.keyCode == 20 { self.snooze("tomorrow") }
                else if [53, 48, 36, 76].contains(e.keyCode) || ch == "n" { self.web.evaluateJavaScript("window.perch && window.perch.snoozeMenu(false)", completionHandler: nil) }
                else { return e }
                return nil
            }
            let list = self.machine.phase == .open || self.machine.phase == .switcher
            // A question on the card: the page keeps which one you are on, so its keys go there.
            if self.machine.phase == .open, self.projects.indices.contains(self.machine.selected),
               let ask = self.projects[self.machine.selected].ask, ask.kind == .question, ask.answerable {
                let keys: [UInt16: String] = [36: "enter", 76: "enter", 51: "back", 123: "back", 124: "next"]
                let k = keys[e.keyCode] ?? (ch.count == 1 && "123456789".contains(ch) ? ch : nil)
                if let k { self.web.evaluateJavaScript("window.perch && window.perch.askKey('\(k)')", completionHandler: nil); self.restartTimer(); return nil }
            }
            if self.machine.phase == .switcher {
                // Typing narrows the list. Backspace edits, Esc clears what you typed before it closes anything.
                if e.keyCode == 51 { if !self.listQuery.isEmpty { self.listQuery.removeLast(); self.filterChanged() }; return nil }
                if e.keyCode == 53, !self.listQuery.isEmpty { self.listQuery = ""; self.filterChanged(); return nil }
                if e.keyCode == 125 || e.keyCode == 126 { self.stepList(e.keyCode == 125 ? 1 : -1); return nil }
                let typed = e.characters ?? ""
                if e.modifierFlags.intersection([.command, .control]).isEmpty, typed.count == 1,
                   typed.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && !(0xF700...0xF8FF).contains($0.value) }) {
                    if !(typed == " " && self.listQuery.isEmpty) { self.listQuery += typed; self.filterChanged() }
                    return nil
                }
                // Nothing left to open or look at when nothing matches.
                if [36, 76, 48, 124].contains(e.keyCode), ListFilter.shown(self.projects, self.listQuery).isEmpty { return nil }
            }
            if self.machine.phase == .switcher, e.keyCode == 124 { self.send(.back); return nil }   // the details of the row you are on
            switch (e.keyCode, ch) {
            case (36, _), (76, _): self.send(.confirm)
            case (53, _): self.send(.dismiss)
            case (48, _): self.send(self.machine.phase == .open ? .openSwitcher : .back)
            case (123, _): if self.machine.phase == .open { self.send(.openSwitcher) } else { return e }   // back to the list, as Right came from it
            case (125, _): self.send(.next)
            case (126, _): self.send(.previous)
            case (_, ","): if list, e.modifierFlags.contains(.command) { self.send(.openSettings) } else { return e }   // Command+comma, on the card and in the list (where letters filter)
            case (_, "r"): if self.machine.phase == .open { self.web.evaluateJavaScript("window.perch && window.perch.replyMenu(true)", completionHandler: nil) } else { return e }
            case (_, "n"): if self.machine.phase == .open { self.web.evaluateJavaScript("window.perch && window.perch.snoozeMenu(true)", completionHandler: nil) } else { return e }
            case (_, "a"), (_, "d"):
                // A permission on the card: A allows, D denies.
                guard self.machine.phase == .open, self.projects.indices.contains(self.machine.selected),
                      let ask = self.projects[self.machine.selected].ask, ask.answerable, ask.kind == .permission else { return e }
                self.answer(ch == "a" ? "allow" : "deny"); return nil
            default: return e
            }
            if self.machine.phase == .open { self.restartTimer(); self.push() }
            return nil
        }
    }
    /// The first row that matches is the one Return opens.
    private func filterChanged() {
        if let first = ListFilter.ordered(projects, listQuery, now: Date()).first { machine.send(.projectsChanged(count: projects.count, selected: first)) }
        push()
    }
    /// Up and down move through the rows that match, wrapping around.
    private func stepList(_ d: Int) {
        let shown = ListFilter.ordered(projects, listQuery, now: Date())
        guard !shown.isEmpty else { return }
        let next = shown.firstIndex(of: machine.selected).map { shown[($0 + d + shown.count) % shown.count] } ?? shown[0]
        machine.send(.projectsChanged(count: projects.count, selected: next))
        push()
    }
    private func stopKeys() { if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil } }

    /// Only a card you asked for takes the keyboard. Hover and Perch speaking up never do: you may be typing elsewhere,
    /// and Return would pick up a session. A click on the card gives it the keyboard. One exception: a card you hovered
    /// open on something to answer. Its number keys, A, D and Esc must reach Perch, not the agent's own prompt in the
    /// app behind, where Esc dismisses the question.
    private var cardTakesKeys: Bool {
        guard !proactiveOpen else { return false }
        guard openedByHover else { return true }
        return machine.phase == .open && projects.indices.contains(machine.selected) && projects[machine.selected].ask?.answerable == true
    }

    // MARK: mouse. Hover pauses the timer; the panel only catches clicks over the visible card.
    private var cursorTimer: Timer?
    private var lastCursor = CGPoint(x: -1, y: -1)

    /// Checks the cursor 30 times a second while it is near the top of a screen or a card is up, and 4 times a second
    /// otherwise. Reliable where mouse-moved events are not, it feeds the character's eyes, and it lets the Mac idle.
    private var cursorFast = true
    private func startCursorPolling() {
        cursorTimer?.invalidate()
        let t = Timer(timeInterval: cursorFast ? 1.0 / 30.0 : 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let at = NSEvent.mouseLocation
                let top = NSScreen.screens.first { $0.frame.contains(at) }.map { $0.frame.maxY - at.y } ?? 0
                let fast = self.machine.phase != .idle || top < 160
                if fast != self.cursorFast { self.cursorFast = fast; self.startCursorPolling(); return }
                self.mouseMoved()
                self.watchLaunchers()
                if self.handCursor, !self.panel.isKeyWindow, self.machine.phase != .idle || self.activityMode == "full" { NSCursor.pointingHand.set() }
                let p = NSEvent.mouseLocation
                // The eyes follow it, and a card or activity WebKit is not telling about the pointer lights what is under it.
                if self.machine.phase != .idle || self.activityMode == "full", self.ready, p != self.lastCursor {
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

    /// macOS ignores a cursor set by an app that is not in front unless the app says it sets the cursor from the background,
    /// and Perch never comes to the front. A private CoreGraphics switch, looked up at run time: without it, no hand.
    private static func setsCursorInBackground() {
        guard let all = dlopen(nil, RTLD_NOW), let conn = dlsym(all, "_CGSDefaultConnection"), let set = dlsym(all, "CGSSetConnectionProperty") else { return }
        typealias Connection = @convention(c) () -> Int32
        typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32
        let me = unsafeBitCast(conn, to: Connection.self)()
        _ = unsafeBitCast(set, to: SetProperty.self)(me, me, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
    }

    /// A click anywhere outside the card closes it, as the button comes up. A press that turns into a drag is decided by
    /// where it ends: on the card (a file from Finder for the reply) the card stays, anywhere else it closes. Not during
    /// onboarding: you click into System Settings in the middle of it.
    private var pressedOutside = false
    /// The drag pasteboard's count when the button went down: it moves on when a drag starts.
    private var dragBase = 0
    private var cardRect: CGRect { NotchGeometry.contentRect(width: contentSize.width, height: contentSize.height, screen: info) }
    private var draggedSincePress: Bool { NSPasteboard(name: .drag).changeCount != dragBase }
    /// The button is down and files are on their way somewhere, dragged since it went down.
    private var draggingFiles: Bool {
        NSEvent.pressedMouseButtons & 1 != 0 && draggedSincePress
            && NSPasteboard(name: .drag).canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }
    private func pressedElsewhere() {
        dragBase = NSPasteboard(name: .drag).changeCount
        pressedOutside = machine.phase != .idle && !cardRect.contains(NSEvent.mouseLocation)
    }
    private func releasedElsewhere() {
        guard pressedOutside else { return }
        pressedOutside = false
        guard machine.phase != .idle, machine.phase != .onboarding, !holdOpen else { return }
        if draggedSincePress, cardRect.contains(NSEvent.mouseLocation) { return }   // dropped on the card
        send(.dismiss)
    }

    /// Another app took the keyboard from the card (Raycast, Spotlight, Command+Tab): you have gone elsewhere, as with a
    /// click outside, so the card makes way rather than cover that app's window. Not during onboarding (you go to System
    /// Settings in the middle of it), nor while a reply is typed or on its way.
    private func makeWay() {
        guard machine.phase != .idle, machine.phase != .onboarding, !holdOpen, !replyOpen, waitingReply == nil else { return }
        // A press in another app took it: the release decides, so a file dragged from there can still land on the card.
        if NSEvent.pressedMouseButtons != 0 { return }
        send(.dismiss)
    }

    /// A card without the keyboard (the welcome card, a hovered one) never hears it go, so while a card is up Perch looks
    /// a few times a second for a launcher that has it. Twice in a row counts, so an app switch in flight does not.
    private var launcherCheck = (tick: 0, hits: 0)
    private func watchLaunchers() {
        guard machine.phase != .idle else { launcherCheck = (0, 0); return }
        launcherCheck.tick += 1
        guard launcherCheck.tick % 8 == 0 else { return }
        let launcher = Quiet.launcherOpen()
        launcherCheck.hits = launcher == nil ? 0 : launcherCheck.hits + 1
        if launcherCheck.hits >= 2 {
            if ProcessInfo.processInfo.environment["PERCH_TRACE"] != nil { NSLog("Perch: \(launcher ?? "") has the keyboard, the card makes way") }
            launcherCheck.hits = 0; makeWay()
        }
    }

    private func installMouseMonitors() {
        startCursorPolling()
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.makeWay() }
        }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] _ in MainActor.assumeIsolated { self?.pressedElsewhere() } }) { mouseMonitors.append(g) }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp, .otherMouseUp], handler: { [weak self] _ in MainActor.assumeIsolated { self?.releasedElsewhere() } }) { mouseMonitors.append(g) }
        let handler: (NSEvent?) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.mouseMoved() } }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: handler) { mouseMonitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { e in handler(e); return e }) { mouseMonitors.append(l) }
    }
    /// The notch plus a little room for the character beside it.
    private func notchHoverRect() -> CGRect {
        let idle = NotchGeometry.idleSize(for: info)
        let w = max(idle.width, 150, activityMode == "wings" ? activitySize.width : 0)
        let left: CGFloat = 30, right: CGFloat = 8     // the character sits just left of the notch
        // Extends above the screen edge so the very top pixel row of the cursor counts.
        return CGRect(x: info.frame.midX - w / 2 - left, y: info.frame.maxY - idle.height - 2, width: w + left + right, height: idle.height + 40)
    }

    /// Resting the cursor on the notch for a moment opens the welcome card.
    private func hoverIdle() {
        let inside = notchHoverRect().contains(NSEvent.mouseLocation)
        if inside != tabHot { tabHot = inside; web.evaluateJavaScript("window.perch && window.perch.hot(\(inside))", completionHandler: nil) }
        if !inside { hoverLatched = false; hoverTask?.cancel(); hoverTask = nil; return }
        // Not while a button is down (a drag in passing), unless it carries files: brought to the notch, they open the card to drop on.
        if hoverLatched || hoverTask != nil || (NSEvent.pressedMouseButtons != 0 && !draggingFiles) { return }
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled else { return }
            self.hoverTask = nil
            if ProcessInfo.processInfo.environment["PERCH_TRACE"] != nil { NSLog("Perch hover: dwell done") }
            // Not over a launcher that has the keyboard: the card would cover it. It opens once the launcher is gone.
            if self.machine.phase == .idle, self.notchHoverRect().contains(NSEvent.mouseLocation), Quiet.launcherOpen() == nil { self.comeBack(byHover: true) }
        }
    }

    private func mouseMoved() {
        if machine.phase == .idle {
            // The tab (or notch) lives on whichever screen the cursor is on, so an external display gets one too.
            if let under = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }), under !== screen { place(on: under); push() }
            // Open, the activity takes clicks (its buttons) and resting on it holds it; it does not open the card.
            let onActivity = activityMode == "full" && activityRect.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)
            if panel.ignoresMouseEvents == onActivity { panel.ignoresMouseEvents = !onActivity }
            if onActivity {
                hoverTask?.cancel(); hoverTask = nil; hoverLatched = true
                if !tabHot { tabHot = true; web.evaluateJavaScript("window.perch && window.perch.hot(true)", completionHandler: nil) }
                return
            }
            hoverIdle(); return
        }
        let rect = NotchGeometry.contentRect(width: contentSize.width, height: contentSize.height, screen: info)
        let inside = rect.contains(NSEvent.mouseLocation)
        panel.ignoresMouseEvents = !inside
        if inside, !pointerOnCard, panel.allowsKey, !panel.isKeyWindow, cardTakesKeys { panel.makeKey() }
        pointerOnCard = inside
        // Writing a reply makes the card yours: it stays when the pointer wanders off, until a click elsewhere or Esc.
        if openedByHover, !replyOpen, Date().timeIntervalSince(openedAt) > 0.5 {
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
