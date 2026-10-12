import CPerchLinux
import Foundation
import PerchCore

/// Linux's NotchController: the Mac's state machine, timings and rules (Sources/Perch/NotchController.swift), over the GTK
/// panel, X11 and /proc. Kept in the Mac file's order, section by section, so a change there finds its place here. What
/// Linux has no counterpart for is left out: the Claude app, the Codex app, Conductor, Accessibility, Sparkle.
@MainActor
final class NotchController {
    private let panel = Panel()
    private var machine: NotchMachine
    private var projects: [Project]
    private let provider: SessionProviding
    private var screen: Screen
    private var info: ScreenInfo
    private var contentSize = CGSize(width: NotchGeometry.cardWidth, height: 160)
    private var timerToken = 0
    private var timer: Task<Void, Never>?
    /// The card hears keys (the Mac's local key monitor).
    private var keysOn = false
    private var ready = false
    /// What you typed in the list to narrow it. Cleared when the card closes.
    private var listQuery = ""
    /// The app icons this page has. Nil until sent, and again after the page reloads.
    private var iconKeys: Set<String>?
    private var iconsCheckedAt = Date.distantPast
    private var snoozeTask: Task<Void, Never>?
    private var hoverTask: Task<Void, Never>?
    /// The cursor is on the tab, so it leans toward you.
    private var tabHot = false
    /// When the cursor left a hover-opened card. It closes only if it stays away for a moment.
    private var leftCardAt: Date?
    /// Opened by resting on the top edge: no countdown, and it closes the moment the cursor leaves the card.
    private var openedByHover = false
    private var openedAt = Date.distantPast
    /// Perch spoke up on its own: it must not take the keyboard from whatever you are typing in. A click gives it focus.
    private var proactiveOpen = false
    /// The "Remind me in" choices are showing in place of the buttons.
    private var snoozeMenuOpen = false
    /// The reply field is showing; keys go to it.
    private var replyOpen = false
    /// What you have typed in each session's reply and not sent, by project id. Kept while Perch runs, not on disk.
    private var drafts: [String: String] = [:]
    /// Nothing on screen and nothing half written.
    var isQuiet: Bool { machine.phase == .idle && drafts.values.allSatisfy { $0.isEmpty } }
    /// What showed when the card or list was put away, for the shortcut to bring back (PutAway).
    private var putAway: PutAway?
    /// The card takes the keyboard when the pointer comes onto it, or when a hovered card gets something to answer: once.
    private var pointerOnCard = false
    private var tookKeysForAsk = false
    /// After a card closes, hovering won't reopen it until the cursor has left the top edge once.
    private var hoverLatched = false
    /// Simulation mode: the welcome card stays until you act on it.
    var holdOpen = false
    /// How long "Not now" hides the card before it comes back.
    var snoozeSeconds: Double = 30 * 60
    /// "Not now" holds until then: coming back from a break does not override it.
    private var snoozedUntil = Date.distantPast
    /// When you last saw each session's latest activity, by session id.
    private var seen = Prefs.seen
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
    /// The scan as it came, before live status and ordering.
    private var base: [Project] = []

    init(provider: SessionProviding, ui: URL) {
        self.provider = provider
        projects = []
        machine = NotchMachine(projectCount: 0)
        screen = Prefs.showOn == .mouse ? ScreenChooser.home() : ScreenChooser.rest()
        info = screen.screenInfo

        panel.onMessage = { [weak self] body in self?.message(body) }
        panel.onLoaded = { [weak self] in guard let self else { return }; self.ready = true; self.iconKeys = nil; self.push() }
        panel.onKey = { [weak self] keyval, keycode, state, isRepeat in
            guard let self else { return false }
            // A modifier going down is the Mac's flagsChanged: the recorder and the held keys hear it, the page gets it too.
            if let mods = KeyMap.flags(keyval: keyval, state: state, pressed: true) { if !isRepeat { self.modifiersChanged(mods) }; return false }
            return self.key(KeyMap.press(keyval: keyval, keycode: keycode, state: state), isRepeat: isRepeat)
        }
        panel.onKeyUp = { [weak self] keyval, state in
            if let mods = KeyMap.flags(keyval: keyval, state: state, pressed: false) { self?.modifiersChanged(mods) }
        }
        // A card that offers Reply: one asking you something has no field to drop into.
        panel.takesFiles = { [weak self] in
            guard let self, self.machine.phase == .open, self.projects.indices.contains(self.machine.selected) else { return false }
            return self.projects[self.machine.selected].ask == nil
        }
        panel.onDrag = { [weak self] n, at in self?.js("window.perch && window.perch.dragOver(\(n), \(at.x), \(at.y))") }
        panel.onFiles = { [weak self] paths in
            guard let self, self.machine.phase == .open else { return false }
            self.addPaths(paths); self.panel.allowsKey = true; self.panel.makeKey(); return true
        }
        place(on: screen)
        panel.load(ui.appendingPathComponent("index.html"))
        panel.show()

        startPointerPolling()
        hookServer.onEvent = { [weak self] e in self?.hookEvent(e) }
        hookServer.onAbandoned = { [weak self] id in self?.askWentAway(id) }
        hookServer.keepHolding = { [weak self] sid in
            guard let self else { return true }
            let here = self.youAreIn().maybe
            return !self.projects.contains { ($0.sessionId ?? $0.id) == sid && here.contains($0.id) }
        }
        hookServer.start()
        startRefreshing()
        startWatchingFocus()
    }

    private func js(_ source: String) { panel.evaluate(source) }

    // MARK: public actions
    /// `proactive` is Perch speaking up on its own (you came back from being away, a snooze ended). Then it never
    /// talks about the session you are already in: that one goes to the back, and if it is the only one, nothing shows.
    /// `reminder` is a "Not now" coming due; it is the one proactive open a snooze allows.
    /// `awaySince` is when you left, for "Finished 12m after you left".
    func comeBack(byHover: Bool = false, proactive: Bool = false, reminder: Bool = false, awaySince: Date? = nil) {
        guard machine.phase == .idle else { return }
        if byHover, putAway?.replying == true, reopen(byHover: true) { return }
        if let since = awaySince { lastAway = (since, Date()) }
        if proactive && !reminder && Date() < snoozedUntil { return }
        // On a call or presenting: hold the card until that is over.
        if proactive, let why = Quiet.reason() { holdUntilQuiet(reminder: reminder, why: why); return }
        if !proactive && !byHover {
            snoozeTask?.cancel(); snoozedUntil = .distantPast; held = nil
            if projects.isEmpty { openWhenScanned = !scannedOnce; toggleSwitcher(); return }
        }
        if proactive {
            let active = youAreIn().maybe
            if reminder {
                guard projects.contains(where: { !active.contains($0.id) }) else { return }
            } else {
                let news = projects.filter { !active.contains($0.id) && isNews($0) }.sorted { ($0.lastActive ?? .distantPast) > ($1.lastActive ?? .distantPast) }
                guard !news.isEmpty else { return }
                let first = Set(news.map(\.id))
                projects = news + projects.filter { !first.contains($0.id) }
            }
            projects = projects.filter { !active.contains($0.id) } + projects.filter { active.contains($0.id) }
        }
        openedByHover = byHover; proactiveOpen = proactive; openedAt = Date(); leftCardAt = nil; prepareToShow(); send(.comeBack)
        refreshProjects()
    }

    // MARK: the live activity
    /// What the panel shows at the top when an answer or a request arrives (app.js activity): "", "wings" or "full".
    private var activityMode = ""
    private var activitySize = CGSize.zero
    /// Registers the keys its buttons answer to, and drops them when it goes.
    var onActivityKeys: (([String]) -> Void)?
    func playActivityDemo() { js("window.perch && window.perch.actDemo()") }
    func activityKey(_ name: String) { js("window.perch && window.perch.actKey('\(name)')") }

    /// The activity grown from the top edge, in screen coordinates.
    private var activityRect: CGRect {
        CGRect(x: info.frame.midX - activitySize.width / 2, y: info.frame.maxY - activitySize.height, width: activitySize.width, height: activitySize.height)
    }

    /// Opens that session's card as if you asked for it, with the keyboard; Reply opens its field.
    private func openCard(for id: String, reply: Bool) {
        guard machine.phase == .idle, let i = projects.firstIndex(where: { $0.id == id }) else { return }
        projects.insert(projects.remove(at: i), at: 0)
        comeBack()
        if reply { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.js("window.perch && window.perch.replyMenu(true)") } }
    }

    /// Calls and presentations, checked at most every few seconds: push() runs often.
    private var quietChecked: (at: Date, on: Bool) = (.distantPast, false)
    private func quietNow() -> Bool {
        if Date().timeIntervalSince(quietChecked.at) > 5 { quietChecked = (Date(), Quiet.reason() != nil) }
        return quietChecked.on
    }

    /// The session you are in (`sure`) and the ones you may be in (`maybe`). On Linux every session lives in a terminal:
    /// the agent in the focused herdr or tmux pane or terminal tab. Where Perch cannot tell which tab is in front, every
    /// live session in that terminal is a maybe: it would rather stay quiet about one of them than nudge you about yours.
    private func youAreIn() -> (sure: Set<String>, maybe: Set<String>) {
        guard let app = FrontApp.id(), Terminals.keys[app] != nil else { return ([], []) }
        if FocusProbe.reads(app), focus.fresh(for: app) == nil, hasSessions(in: app) { focus.poll(app: app) }
        let r = Focus.inTerminal(projects, app: app, looking: focus.fresh(for: app)?.looking ?? .cannotTell)
        traceFocus(app, r)
        return r
    }
    private let focus = FocusProbe()
    private func hasSessions(in app: String) -> Bool { projects.contains { $0.terminal && $0.via == app && $0.spot != nil } }
    private var traced = ""
    private func traceFocus(_ app: String, _ r: (sure: Set<String>, maybe: Set<String>)) {
        guard Trace.on else { return }
        let line = "\(app) looking \(focus.fresh(for: app)?.looking.spots.sorted() ?? []) unknown=\(focus.fresh(for: app)?.looking.unknown ?? true) sure=\(r.sure.sorted()) maybe=\(r.maybe.sorted())"
        if line != traced { traced = line; Trace.log("Perch in: \(line)") }
    }
    /// The app in front, a second apart: a switch is seen before anything arrives (the Mac hears it from NSWorkspace).
    private var lastFront: String?
    private var lastScreens: [Screen] = []
    private func startWatchingFocus() {
        focus.changed = { [weak self] in if self?.machine.phase == .idle { self?.push() } }
        lastScreens = Screen.screens
        var tick = 0
        GLoop.every(1) { [weak self] in
            guard let self else { return false }
            tick += 1
            let front = FrontApp.id()
            if front != self.lastFront { self.lastFront = front; self.activated(front) }
            if let front, FocusProbe.reads(front), self.hasSessions(in: front) { self.focus.tick(app: front) }
            if tick % 3 == 0 { self.checkScreens() }
            return true
        }
    }
    /// Another app came to the front (NSWorkspace.didActivateApplicationNotification on the Mac).
    private func activated(_ app: String?) {
        if let app {
            // Pick up opens a closed terminal session in the terminal you use.
            if Terminals.keys[app] != nil { Prefs.lastTerminal = app }
            if FocusProbe.reads(app), hasSessions(in: app) { focus.poll(app: app) }
        }
        // Following the active window, the resting panel goes where the app you switched to is.
        if machine.phase == .idle, Prefs.showOn == .window { let to = ScreenChooser.rest(); if to != screen { place(on: to) } }
        if machine.phase == .idle { push() }
    }
    /// Displays came or went (didChangeScreenParametersNotification on the Mac).
    private func checkScreens() {
        let now = Screen.screens
        guard now != lastScreens else { return }
        lastScreens = now
        if machine.phase == .settings { push(); return }
        guard machine.phase == .idle else { return }
        place(on: ScreenChooser.rest()); push()
    }

    /// The shortcut tapped: close whatever is showing, or bring back what you put away a moment ago, else open the list.
    func chordTap() {
        if recorder != nil { return }
        if machine.phase == .onboarding, onbStep == shortcutStep { shortcutTried = true; shortcutSaved = false; push(); return }
        guard machine.phase == .idle else { send(.dismiss); return }
        if !reopen() { toggleSwitcher() }
    }

    /// The card or list you put away in the last few minutes, as you left it. False when there is nothing to bring back.
    private func reopen(byHover: Bool = false) -> Bool {
        guard let away = putAway else { return false }
        guard let event = away.recall(ids: projects.map(\.id), now: Date()) else { putAway = nil; return false }
        openedByHover = byHover; proactiveOpen = false; openedAt = Date(); leftCardAt = nil; prepareToShow()
        if away.phase == .switcher { listQuery = away.query }
        send(event)
        guard machine.phase != .idle else { return false }
        if machine.phase == .switcher, case .reopen(_, nil) = event { filterChanged() }
        if away.replying { js("window.perch && window.perch.replyMenu(true)") }
        refreshProjects()
        return true
    }
    func toggleSwitcher() {
        let fromIdle = machine.phase == .idle
        openedByHover = false; proactiveOpen = false; prepareToShow()
        send(.openSwitcher)
        if fromIdle, machine.phase == .switcher, let top = ListFilter.ordered(projects, "", now: Date()).first {
            machine.send(.projectsChanged(count: projects.count, selected: top)); push()
        }
        refreshProjects()
    }
    func confirm() { send(.confirm) }

    // MARK: state
    /// A hover opens the card on the display whose top edge you hovered; the shortcut and Perch on its own open it
    /// where Show Perch on says.
    private func prepareToShow() {
        guard machine.phase == .idle else { return }
        place(on: openedByHover ? ScreenChooser.current() : ScreenChooser.target())
    }

    // MARK: keeping the project list fresh, off the main thread
    private var refreshing = false
    private var pendingProjects: [Project]?
    private var refreshAgain = false

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

    // MARK: watching the session folders, so a new message shows up within a moment
    private var watcher: Watcher?
    private var fsPending = false

    private func startWatching() {
        // Every agent's session folders, including ones that appear later (an agent installed while Perch runs).
        let w = Watcher()
        w.onChange = { [weak self] in self?.sessionFilesChanged() }
        w.start()
        watcher = w
    }

    /// A busy session writes many times a second, so refreshes are spaced apart: half a second while a card or the list is
    /// up, three while Perch rests.
    private func sessionFilesChanged() {
        guard !fsPending else { return }
        fsPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + (machine.phase == .idle ? 3.0 : 0.5)) { [weak self] in
            MainActor.assumeIsolated { self?.fsPending = false; self?.refreshProjects() }
        }
    }

    // MARK: what you have seen
    private func isFresh(_ p: Project) -> Bool {
        guard let t = p.lastActive, t > newsSince else { return false }
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

    /// Sessions from before Perch was installed are not news. The session you are in counts as seen while you are here.
    private func noteSeen() {
        if !Prefs.seenBaselined { projects.forEach(markSeen); Prefs.seenBaselined = true }
        if ActivityMonitor.idleSeconds() < 60 { let here = youAreIn().sure; projects.filter { here.contains($0.id) }.forEach(markSeen) }
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
        Trace.log("Perch: holding the welcome card, \(why)")
        held = (reminder || (held?.reminder ?? false), Date().addingTimeInterval(3 * 3600))
        guard heldTask == nil else { return }
        heldTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, let h = self.held else { break }
                if Date() > h.until { self.held = nil; break }
                guard self.machine.phase == .idle, Quiet.reason() == nil else { continue }
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
        for a in before?.asks ?? [] where !now.asks.contains(where: { $0.id == a.id }) { hookServer.release(a.id) }
        live[e.sessionId] = now
        if live.count > 120 { live = Dictionary(uniqueKeysWithValues: live.sorted { $0.value.at > $1.value.at }.prefix(80).map { ($0.key, $0.value) }) }
        Trace.log("Perch hook: \(e.agent) \(e.sessionId.prefix(8)) \(e.kind)")
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
        guard projects.indices.contains(i), let ask = projects[i].ask, ask.answerable else {
            if projects.indices.contains(i) { notSent(projects[i].id) }
            return
        }
        let p = projects[i]
        hookServer.answer(ask.id, with: answers.map { ask.reply(answers: $0) } ?? ask.reply(choice)) { [weak self] delivered in
            if !delivered { self?.notSent(p.id) }
        }
        if let sid = p.sessionId { live[sid]?.settle(ask.id, at: Date()) }
        markSeen(p)
        let onCard = machine.phase != .idle
        send(.dismiss)
        if onCard || putAway?.session == p.id { putAway = nil }
        redecorate()
    }

    private func notSent(_ id: String) {
        guard let data = try? JSONEncoder().encode(id), let arg = String(data: data, encoding: .utf8) else { return }
        js("window.perch && window.perch.notSent(\(arg))")
    }

    private func startRefreshing() {
        refreshProjects()
        startWatching()
        // Every 5 seconds while the card is up, every 20 otherwise.
        var tick = 0
        GLoop.every(5) { [weak self] in
            guard let self else { return false }
            tick += 1
            if self.machine.phase == .open || self.machine.phase == .switcher || tick % 4 == 0 { self.refreshProjects() }
            return true
        }
    }

    /// Moving to another display, the panel would show what it last drew for the old one until the page draws again. So it
    /// goes see-through, moves, and shows again once the page has drawn for its new place (`painted`), or after a moment.
    private var revealToken = 0
    private var revealPending = false
    private func place(on s: Screen) {
        let moving = s.frame != info.frame
        if moving { Trace.log("Perch screen: \(s.localizedName), cursor at \(Mouse.location)") }
        screen = s; info = s.screenInfo
        if moving, tabHot { tabHot = false; js("window.perch && window.perch.hot(false)") }
        if moving, ready {
            panel.alphaValue = 0
            revealToken += 1; revealPending = true
            let token = revealToken
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.reveal(token) }
        }
        panel.setFrame(NotchGeometry.panelFrame(for: info))
    }
    private func reveal(_ token: Int) {
        guard token == revealToken else { return }
        panel.alphaValue = 1
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
        if old != .idle || putAway?.session == projects[index].id { putAway = nil }
        push()
    }

    private func push() {
        trackViewing()
        guard ready else { return }
        let away = awaySinceForCard, now = Date()
        let fresh = Set(projects.filter(isFresh).map(\.id))
        let lines = Dictionary(projects.map { p in (p.id, WhileAway.line(kind: p.status.kind, lastActive: p.lastActive, now: now, awaySince: away, fresh: fresh.contains(p.id))) }, uniquingKeysWith: { a, _ in a })
        var sent = UISnapshot(machine: machine, projects: projects, screen: info, timerToken: timerToken, icons: iconsToSend(), allowAutoCollapse: proactiveOpen && !holdOpen && !openedByHover && !snoozeMenuOpen && !replyOpen,
                              activeId: nil, activeIds: machine.phase == .idle ? youAreIn().maybe.sorted() : [],
                              scanning: !scannedOnce, canSend: true, fresh: fresh, lines: lines,
                              onboarding: machine.phase == .onboarding ? onboardingState() : nil,
                              settings: machine.phase == .settings ? settingsState() : nil)
        sent.platform = "linux"
        if machine.phase == .switcher { sent.query = listQuery; sent.shown = ListFilter.ordered(projects, listQuery, now: Date()) }
        if machine.phase == .idle { sent.quiet = quietNow() }
        sent.drafts = drafts
        sent.proactive = proactiveOpen
        let askTakesKeys = machine.phase == .open && openedByHover && cardTakesKeys
        if askTakesKeys, !tookKeysForAsk, panel.allowsKey, !panel.isKeyWindow { panel.makeKey() }
        tookKeysForAsk = askTakesKeys
        guard let data = try? JSONEncoder().encode(sent), let json = String(data: data, encoding: .utf8) else { return }
        js("window.perch && window.perch.apply(\(json))")
        if revealPending { revealPending = false; js("window.perch && window.perch.painted(\(revealToken))") }
    }

    /// Icons go once per page load. An app missing from them (installed later) is looked for again each minute.
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
        if old != new { stopRecording(); shortcutTried = false; shortcutSaved = false }
        if old == .onboarding { Prefs.onboarded = true; onbTask?.cancel() }
        Trace.log("Perch phase: \(old) -> \(new)")
        switch new {
        case .idle:
            if old == .open || old == .switcher {
                putAway = PutAway(phase: old, session: projects.indices.contains(machine.selected) ? projects[machine.selected].id : nil,
                                  query: listQuery, replying: replyOpen, at: Date())
            }
            hoverLatched = true; snoozeMenuOpen = false; replyOpen = false; listQuery = ""; pointerOnCard = false
            closedAt = Date(); awayForHover = false
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(700))
                guard let self, self.machine.phase == .idle else { return }
                self.place(on: ScreenChooser.rest())
                if let pending = self.pendingProjects { self.pendingProjects = nil; self.install(pending) } else { self.push() }
                self.refreshProjects()
            }
            timer?.cancel(); keysOn = false
            // The card had the keyboard: hand it back to the window you were in.
            panel.resignKey()
            panel.allowsKey = false; panel.ignoresMouseEvents = true
        case .open:
            keysOn = true; panel.allowsKey = true; panel.ignoresMouseEvents = false; if cardTakesKeys { panel.makeKey() }
            restartTimer()
        case .switcher:
            timer?.cancel()
            keysOn = true; panel.allowsKey = true; panel.ignoresMouseEvents = false; if !openedByHover && !proactiveOpen { panel.makeKey() }
        case .onboarding:
            keysOn = true; panel.allowsKey = true; panel.ignoresMouseEvents = false; panel.makeKey()
            watchOnboarding()
        case .settings:
            keysOn = true; panel.allowsKey = true; panel.ignoresMouseEvents = false; panel.makeKey()
            watchOnboarding()
        case .restoring:
            timer?.cancel()
            timer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(3.2))
                if !Task.isCancelled { self?.send(.restoreFinished) }
            }
        }
        updateClickRect()
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

    // MARK: the page
    private func message(_ body: [String: Any]) {
        guard let type = body["type"] as? String else { return }
        switch type {
        case "confirm": send(.confirm)
        case "flip": send(.next)
        case "answer":
            if let a = body["answers"] as? [String: String] { answer("", answers: a) }
            else if let c = body["choice"] as? String { answer(c) }
        case "pick": if let i = int(body["index"]) { send(.select(i)) }
        case "details": if let i = int(body["index"]) { send(.show(i)) }
        case "hooks":
            let on = body["on"] as? Bool ?? true
            for agent in HookInstaller.agents where (Prefs.enabledSources.contains(agent) && (["claude", "codex"].contains(agent) || AgentPresence.installed(.of(agent)))) || !on {
                do { if on { try HookInstaller.install(agent) } else { try HookInstaller.uninstall(agent) } }
                catch { Trace.log("Perch: hooks for \(agent): \(error.localizedDescription)", always: true) }
            }
            push()
        case "dismiss": send(.dismiss)
        case "snooze": snooze(body["when"] as? String ?? "30m")
        case "replyMenu":
            replyOpen = body["open"] as? Bool ?? false
            if replyOpen { timer?.cancel(); panel.makeKey() } else { restartTimer() }
            push()
        case "reply": if let t = body["text"] as? String { reply(t, closeAfter: double(body["close"]) ?? 0.78) }
        case "draft": if let id = body["id"] as? String { drafts[id] = (body["text"] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        case "snoozeMenu":
            snoozeMenuOpen = body["open"] as? Bool ?? false
            if snoozeMenuOpen { timer?.cancel() } else { restartTimer() }
            push()
        case "switcher": send(.openSwitcher)
        case "back": send(.back)
        case "onb": if let a = body["action"] as? String { onboardingAction(a) }
        case "shortcut": if let a = body["action"] as? String { shortcutAction(a) }
        case "settings": if machine.phase == .idle { place(on: ScreenChooser.target()); proactiveOpen = false; openedByHover = false }; send(.openSettings)
        case "setting":
            if let key = body["key"] as? String {
                if key == "idleMinutes", let v = int(body["value"]) { Prefs.idleMinutes = v; onIdleMinutesChanged?(v) }
                if key == "questionSeconds", let v = int(body["value"]), [30, 60, 300].contains(v) { Prefs.questionSeconds = v }
                if key == "hoverExternal", let on = body["value"] as? Bool { Prefs.hoverExternal = on }
                if key == "showOn", let raw = body["value"] as? String {
                    let choice = ShowOn(raw: raw)
                    Prefs.showOn = choice
                    if case .display(let id) = choice { Prefs.showOnName = Screen.screens.first { $0.displayID == id }?.localizedName ?? Prefs.showOnName } else { Prefs.showOnName = nil }
                }
                if key == "login", let on = body["value"] as? Bool { Autostart.set(on) }
                push()
            }
        case "onbOpen":
            let step = int(body["step"]) ?? 0
            if body["only"] as? Bool == true, machine.phase == .settings {
                onbStep = step; onbOnly = true; onbBackToSettings = true
                send(.openOnboarding)
                if step == shortcutStep { shortcutAction("record") }
            } else {
                send(.dismiss)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.startOnboarding(step: step) }
            }
        case "quit": onQuit?()
        case "menuIcon":
            if let s = body["png"] as? String, let comma = s.firstIndex(of: ","), let data = Data(base64Encoded: String(s[s.index(after: comma)...])) {
                onMenuIcon?(data)
            }
        case "source":
            if let id = body["id"] as? String, let on = body["enabled"] as? Bool {
                var set = Prefs.enabledSources
                if on { set.insert(id) } else { set.remove(id) }
                Prefs.enabledSources = set
                refreshProjects(); push()
            }
        case "notify":
            if let kind = body["kind"] as? String, let on = body["enabled"] as? Bool {
                Prefs.notifyOff = NotifyKinds.toggled(Prefs.notifyOff, kind: kind, enabled: on)
                push()
            }
        case "character":
            if let shape = body["shape"] as? String { Prefs.shape = shape }
            if let color = body["color"] as? String { Prefs.color = color }
        case "choose": if let i = int(body["index"]) { send(.choose(i)) }
        case "painted": if let t = int(body["token"]) { reveal(t) }
        case "size":
            if let w = double(body["width"]), let h = double(body["height"]) { contentSize = CGSize(width: w, height: h); updateClickRect() }
        case "activity":
            let wasShowing = activityMode != ""
            activityMode = body["mode"] as? String ?? ""
            if !wasShowing, activityMode != "", Prefs.showOn == .window, machine.phase == .idle, !awayForHover {
                let to = ScreenChooser.rest(); if to != screen { place(on: to); push() }
            }
            if let w = double(body["width"]), let h = double(body["height"]) { activitySize = CGSize(width: w, height: h) }
            if activityMode != "full" { hoverLatched = true }
            onActivityKeys?(body["keys"] as? [String] ?? [])
            updateClickRect()
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
        case "log": Trace.log("Perch UI: \(body["text"] ?? "")", always: true)
        default: break
        }
    }
    /// JSON numbers arrive as NSNumber: Int or Double either way.
    private func int(_ v: Any?) -> Int? { (v as? NSNumber)?.intValue ?? (v as? Int) }
    private func double(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue ?? (v as? Double) }
    var onQuit: (() -> Void)?

    /// "Not now": hide the card and bring it back later (30 minutes, 2 hours, or 9 in the morning).
    private func snooze(_ when: String) {
        let seconds: Double
        switch when {
        case "2h": seconds = 2 * 3600
        case "tomorrow":
            let cal = Calendar.current
            let next = cal.nextDate(after: Date(), matching: DateComponents(hour: 9, minute: 0), matchingPolicy: .nextTime) ?? Date().addingTimeInterval(12 * 3600)
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

    // MARK: replies
    /// A terminal session takes the words straight into its pane or tab, and you stay where you are. A closed one opens
    /// again with your words as its first message. Only a terminal Perch cannot type into falls back to pasting.
    /// `closeAfter`: when the card closes, so the send animation lands first (the page says).
    private func reply(_ text: String, to pid: String? = nil, closeAfter: Double = 0.78) {
        guard let i = projectIndex(pid) else { return }
        let p = projects[i]
        drafts[p.id] = nil
        guard p.terminal, let cwd = p.cwd, let id = p.sessionId else { pasteReply(text, to: p.id); return }
        let agent = p.app, line = text.replacingOccurrences(of: "\n", with: " "), runningPid = p.pid
        let sentAt = Date(), back = WhereYouWere.now()
        markSeen(p)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let live = LiveSessions.all()
            let hit = live.first { $0.pid == runningPid && $0.agent == agent } ?? live.first { $0.agent == agent && $0.argv.contains(id) }
            let (done, reopened): (Bool, Bool)
            if let hit { (done, reopened) = (Terminals.type(line, into: hit), false) }
            else {
                _ = Restorer.reopen(agent: agent, session: id, cwd: cwd, command: Agent.of(agent).resume(id, prompt: line))
                (done, reopened) = (true, true)
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    guard done else { self.pasteReply(text, to: p.id); return }
                    // It carries on in its new window; you go back to what you were doing.
                    if reopened { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { back.restore() } }
                    DispatchQueue.main.asyncAfter(deadline: .now() + max(0, closeAfter - Date().timeIntervalSince(sentAt))) {
                        guard self.machine.phase == .open else { return }
                        let old = self.machine.phase; self.machine.send(.dismiss); self.phaseChanged(old, self.machine.phase); self.putAway = nil; self.push()
                    }
                }
            }
        }
    }
    private func projectIndex(_ pid: String?) -> Int? {
        if let pid { return projects.firstIndex { $0.id == pid } }
        return projects.indices.contains(machine.selected) ? machine.selected : nil
    }

    /// Reply by pasting: Pick up brings the session forward, then the words are pasted (Ctrl+Shift+V, a terminal's paste)
    /// and sent. Then you are put back where you were, and your clipboard is put back.
    private func pasteReply(_ text: String, to pid: String? = nil) {
        guard let i = projectIndex(pid) else { return }
        let back = WhereYouWere.now()
        let saved = Clipboard.save()
        Clipboard.set(text)
        let app = Agent.of(projects[i].app).short
        pickUp(i) { [weak self] landing in
            let target: String, settle: () async -> Bool
            switch landing {
            case .app(let a, exact: true):
                target = a
                settle = { try? await Task.sleep(for: .seconds(0.6)); return true }
            case .newTerminal(let a, let cwd, let agent):
                // Type only once the agent is running, never into the shell before it.
                target = a
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
                Trace.log("Perch: reply left on the clipboard (no exact session to type into)", always: true); self?.say("Reply copied"); return
            }
            Task {
                for _ in 0..<50 {
                    if FrontApp.id() == target { break }
                    try? await Task.sleep(for: .milliseconds(100))
                }
                guard await settle(), FrontApp.id() == target else {
                    Trace.log("Perch: reply left on the clipboard (\(target) did not come forward)", always: true); self?.say("Paste in \(app)"); return
                }
                FakeKeys.tap(keysym: 0x76, ctrl: true, shift: true)   // v
                try? await Task.sleep(for: .milliseconds(250))
                FakeKeys.tap(keysym: 0xff0d)                          // Return
                Trace.log("Perch: sent reply into \(target)", always: true)
                try? await Task.sleep(for: .milliseconds(600))
                Clipboard.restore(saved)
                back.restore()
            }
        }
    }

    /// Files dropped on the card or pasted from the file manager: their paths go into the reply.
    private func addPaths(_ paths: [String]) {
        guard let data = try? JSONEncoder().encode(paths), let json = String(data: data, encoding: .utf8) else { return }
        js("window.perch && window.perch.paths(\(json))")
    }

    /// A word at the top once the card has closed, when something did not go as you would expect.
    private func say(_ text: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            let arg = (try? JSONEncoder().encode(text)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
            self?.js("window.perch && window.perch.say(\(arg))")
        }
    }

    // MARK: settings
    var onIdleMinutesChanged: ((Int) -> Void)?

    /// The agents Settings and onboarding offer: Claude and Codex always, the others once they are on this machine.
    private func sourcesState() -> [UISnapshot.Source] {
        let counts = (provider as? RealSessionProvider)?.counts ?? [:]
        let on = Prefs.enabledSources
        return Agent.all.filter { ["claude", "codex"].contains($0.id) || (counts[$0.id]?.count ?? 0) > 0 || AgentPresence.installed($0) }.map { a in
            UISnapshot.Source(id: a.id, name: a.name, count: counts[a.id]?.count ?? 0, names: counts[a.id]?.names ?? [], enabled: on.contains(a.id))
        }
    }

    private func settingsState() -> UISnapshot.Settings {
        UISnapshot.Settings(sources: sourcesState(), accessibility: true,
                            idleMinutes: Prefs.idleMinutes, questionSeconds: Prefs.questionSeconds, login: Autostart.isOn, live: liveState,
                            hasExternal: !Screen.screens.isEmpty, hoverExternal: Prefs.hoverExternal,
                            showOn: Prefs.showOn.raw, displays: displaysState(), shortcut: shortcutState(),
                            back: machine.settingsFrom != nil)
    }
    /// The connected displays, then a chosen one that is not connected, under the name it had when chosen.
    private func displaysState() -> [UISnapshot.Display] {
        var all = Screen.screens.map { UISnapshot.Display(id: $0.displayID, name: $0.localizedName, connected: true) }
        if case .display(let id) = Prefs.showOn, !all.contains(where: { $0.id == id }) {
            all.append(UISnapshot.Display(id: id, name: Prefs.showOnName ?? "Display", connected: false))
        }
        return all
    }

    /// "on" when every enabled agent on this machine has Perch's hook installed.
    private var liveState: String {
        let on = Prefs.enabledSources.filter { id in HookInstaller.agents.contains(id) && (["claude", "codex"].contains(id) || AgentPresence.installed(.of(id))) }
        return !on.isEmpty && on.allSatisfy(HookInstaller.isInstalled) ? "on" : "off"
    }

    // MARK: onboarding
    /// The hello after setup. For trying it out (`--hello`).
    func sayHello() { js("window.perch && window.perch.hi()") }
    /// The page drew your character for the tray: PNG data.
    var onMenuIcon: ((Data) -> Void)?
    private var onbStep = 0
    /// The Mac's step ids (hello, look, Accessibility, shortcut, apps, live status, all set); the page counts five on Linux.
    let onbTotal = 7
    /// The step that records the shortcut, and the one that lists the apps.
    let shortcutStep = 3
    let appsStep = 4
    /// The Mac's Accessibility step: skipped on Linux, where nothing needs it.
    private let accessibilityStep = 2
    private var onbTask: Task<Void, Never>?
    /// Just the character step (Settings or the menu), not the whole setup.
    private var onbOnly = false
    /// Done and Esc return to Settings, where it was opened from.
    private var onbBackToSettings = false

    func startOnboarding(step: Int = 0, characterOnly: Bool = false) {
        guard machine.phase == .idle else { return }
        onbStep = step == accessibilityStep ? step + 1 : step; onbOnly = characterOnly; onbBackToSettings = false
        snoozeTask?.cancel(); openedByHover = false; proactiveOpen = false
        place(on: ScreenChooser.target())
        if step >= appsStep { refreshProjects() }
        send(.openOnboarding)
    }

    private func onboardingState() -> UISnapshot.Onboarding {
        UISnapshot.Onboarding(step: onbStep, total: onbTotal, accessibility: true, scanning: !scannedOnce, sources: sourcesState(), only: onbOnly, live: liveState, shortcut: shortcutState())
    }

    /// Leaves the character page: back to Settings when it came from there, otherwise closed.
    private func finishCharacter() {
        if onbBackToSettings { send(.openSettings) } else { send(.dismiss) }
    }

    private func onboardingAction(_ action: String) {
        switch action {
        case "next":
            if onbOnly {
                if let chosen = recorder?.pending {
                    finishRecording(.record(chosen))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                        guard let self, self.machine.phase == .onboarding, self.onbOnly, self.shortcutSaved else { return }
                        self.finishCharacter()
                    }
                    return
                }
                finishCharacter(); return
            }
            onbStep = min(onbStep + 1, onbTotal - 1)
            if onbStep == accessibilityStep { onbStep += 1 }   // no Accessibility on Linux: the page skips it too
            if onbStep == appsStep { refreshProjects() }
            stopRecording(); shortcutTried = false; shortcutSaved = false
        case "back":
            onbStep = max(onbStep - 1, 0)
            if onbStep == accessibilityStep { onbStep -= 1 }
            stopRecording(); shortcutTried = false; shortcutSaved = false
        case "finish": send(.dismiss); return
        case "restart": relaunch(); return
        default: break
        }
        push()
    }

    /// Starts a fresh copy of Perch and quits this one.
    private func relaunch() {
        Prefs.resumeStep = onbStep
        let exe = URL(fileURLWithPath: "/proc/self/exe").resolvingSymlinksInPath().path
        let task = Process(); task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.8; exec \(Terminals.shellQuote(exe)) >/dev/null 2>&1 &"]
        try? task.run()
        onQuit?()
    }

    /// While onboarding or Settings is up, notice changes within a second (the scan, sources, hooks).
    private func watchOnboarding() {
        onbTask?.cancel()
        onbTask = Task { [weak self] in
            var last = ""
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(700))
                guard let self, self.machine.phase == .onboarding || self.machine.phase == .settings else { return }
                let key = "\(self.scannedOnce)|\(self.projects.count)|\(Prefs.enabledSources.sorted())|\(self.liveState)|\(Autostart.isOn)"
                if key != last { last = key; self.push() }
            }
        }
    }

    // MARK: the shortcut that opens Perch
    /// Called with true while a new shortcut is being recorded (the old one is paused) and false after (it is applied again).
    var onShortcutRecording: ((Bool) -> Void)?
    /// Whether a combo shortcut is really grabbed (another app may hold it).
    var openComboWorks: (() -> Bool)?
    private var recorder: ShortcutRecorder?
    private var shortcutError = ""
    private var shortcutTried = false
    private var shortcutSaved = false
    private var shortcutAttempt: [String] = []
    private var shortcutPending: [String] = []
    private var shortcutPicks = 0
    private var shortcutRefusals = 0

    private func shortcutState() -> UISnapshot.ShortcutState {
        let s = Prefs.openShortcut
        var works = true, why = ""
        if s.kind == .combo, openComboWorks?() == false { works = false; why = "Another app already uses this shortcut. Record a different one." }
        return UISnapshot.ShortcutState(keys: s.keys, kind: s.kind.rawValue, custom: !s.isStandard, recording: recorder != nil, error: shortcutError, tried: shortcutTried, saved: shortcutSaved, works: works, why: why, attempt: shortcutAttempt, refusals: shortcutRefusals, pending: shortcutPending, picks: shortcutPicks)
    }

    private func shortcutAction(_ action: String) {
        Trace.log("Perch shortcut action: \(action)")
        switch action {
        case "record":
            guard recorder == nil else { return }
            recorder = ShortcutRecorder(); shortcutError = ""; shortcutAttempt = []; shortcutPending = []; shortcutTried = false; shortcutSaved = false
            onShortcutRecording?(true)
        case "cancel": stopRecording()
        case "reset": Prefs.openShortcut = .standard; shortcutTried = false; shortcutSaved = true; recorder = nil; shortcutError = ""; onShortcutRecording?(false)
        default: break
        }
        push()
    }

    private func stopRecording() {
        guard recorder != nil else { return }
        recorder = nil; shortcutError = ""; shortcutAttempt = []; shortcutPending = []
        onShortcutRecording?(false)
    }

    private func finishRecording(_ outcome: ShortcutRecorder.Outcome) {
        if outcome != .none { Trace.log("Perch shortcut: \(outcome)") }
        switch outcome {
        case .none: return
        case .cancel:
            stopRecording()
            if machine.phase == .onboarding, onbOnly { finishCharacter(); return }
        case .refused(let why, let keys): shortcutError = why; shortcutAttempt = keys; shortcutRefusals += 1
        case .chosen(let s): shortcutPending = s.keys; shortcutPicks += 1; shortcutError = ""; shortcutAttempt = []
        case .record(let s): Prefs.openShortcut = s; shortcutTried = false; shortcutSaved = true; recorder = nil; shortcutError = ""; shortcutAttempt = []; shortcutPending = []; onShortcutRecording?(false)
        }
        push()
    }

    /// The modifiers held changed: the recorder hears it, and the shortcut step's big keys show what you hold.
    private func modifiersChanged(_ mods: ShortcutMods) {
        guard keysOn, machine.phase != .idle else { return }
        if recorder != nil { finishRecording(recorder?.flagsChanged(mods: mods) ?? .none) }
        guard machine.phase == .onboarding || machine.phase == .settings,
              let data = try? JSONSerialization.data(withJSONObject: mods.glyphs), let json = String(data: data, encoding: .utf8) else { return }
        js("window.perch && window.perch.held(\(json))")
    }

    // MARK: keys
    /// A key on the card, before the page sees it. True when Perch took it. The Mac's key monitor, key for key; the
    /// shortcut to Settings is Ctrl+comma here (Linux's convention), Super+comma too.
    private func key(_ e: KeyPress, isRepeat: Bool) -> Bool {
        guard keysOn, machine.phase != .idle else { return false }
        if recorder != nil { if !isRepeat { finishRecording(recorder?.keyDown(keyCode: e.keyCode, typed: e.typed, mods: e.mods) ?? .none) }; return true }
        Trace.log("Perch key: \(e.keyCode) in \(machine.phase)")
        let code = e.keyCode
        let ch = KeyLayout.shortcut(typed: e.typed, keyCode: UInt16(clamping: max(0, code)))
        let settingsKey = ch == "," && (e.mods.contains(.control) || e.mods.contains(.command))
        if machine.phase == .onboarding {
            if ch == "s" { js("window.perch && window.perch.onbKey('skip')"); return true }
            if ch == "c", e.mods.intersection([.command, .control, .option]).isEmpty { js("window.perch && window.perch.onbKey('change')"); return true }
            switch code {
            case 36, 76: js("window.perch && window.perch.onbKey('enter')")
            case 123: js("window.perch && window.perch.onbKey('left')")
            case 124: js("window.perch && window.perch.onbKey('right')")
            case 125: js("window.perch && window.perch.onbKey('down')")
            case 126: js("window.perch && window.perch.onbKey('up')")
            case 53: if onbOnly { finishCharacter() } else { send(.dismiss) }
            default: return false
            }
            return true
        }
        if machine.phase == .settings {
            if settingsKey { send(.back); return true }
            let keys: [Int: String] = [36: "enter", 76: "enter", 49: "enter", 123: "left", 124: "right", 125: "down", 126: "up"]
            if let k = keys[code] { js("window.perch && window.perch.setKey('\(k)')"); return true }
            if code == 53 { js("window.perch && window.perch.setKey('esc')"); return true }
            return false
        }
        if replyOpen {
            if code == 53 { js("window.perch && window.perch.replyMenu(false)"); return true }
            // A file copied in the file manager pastes as its path, not its name. WebKit handles the other edit keys itself.
            if ch == "v", e.mods.subtracting(.shift) == .control, Clipboard.filePaths(then: { [weak self] paths in
                if paths.isEmpty { return }
                self?.addPaths(paths)
            }) { return true }
            return false
        }
        if snoozeMenuOpen {
            if ch == "1" || code == 18 { snooze("30m") }
            else if ch == "2" || code == 19 { snooze("2h") }
            else if ch == "3" || code == 20 { snooze("tomorrow") }
            else if [53, 48, 36, 76].contains(code) || ch == "n" { js("window.perch && window.perch.snoozeMenu(false)") }
            else { return false }
            return true
        }
        let list = machine.phase == .open || machine.phase == .switcher
        if machine.phase == .open, projects.indices.contains(machine.selected),
           let ask = projects[machine.selected].ask, ask.kind == .question, ask.answerable {
            let keys: [Int: String] = [36: "enter", 76: "enter", 51: "back", 123: "back", 124: "next"]
            let k = keys[code] ?? (ch.count == 1 && "123456789".contains(ch) ? ch : nil)
            if let k { js("window.perch && window.perch.askKey('\(k)')"); restartTimer(); return true }
        }
        if machine.phase == .switcher {
            if code == 51 { if !listQuery.isEmpty { listQuery.removeLast(); filterChanged() }; return true }
            if code == 53, !listQuery.isEmpty { listQuery = ""; filterChanged(); return true }
            if code == 125 || code == 126 { stepList(code == 125 ? 1 : -1); return true }
            let typed = e.characters ?? ""
            if e.mods.intersection([.command, .control]).isEmpty, typed.count == 1,
               typed.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
                if !(typed == " " && listQuery.isEmpty) { listQuery += typed; filterChanged() }
                return true
            }
            if [36, 76, 48, 124].contains(code), ListFilter.shown(projects, listQuery).isEmpty { return true }
        }
        if machine.phase == .switcher, code == 124 { send(.back); return true }
        switch (code, ch) {
        case (36, _), (76, _): send(.confirm)
        case (53, _): send(.dismiss)
        case (48, _): send(machine.phase == .open ? .openSwitcher : .back)
        case (123, _): if machine.phase == .open { send(.openSwitcher) } else { return false }
        case (125, _): send(.next)
        case (126, _): send(.previous)
        case (_, ","): if list, settingsKey { send(.openSettings) } else { return false }
        case (_, "r"):
            let asking = projects.indices.contains(machine.selected) && projects[machine.selected].ask != nil
            if machine.phase == .open, !asking { js("window.perch && window.perch.replyMenu(true)") } else { return false }
        case (_, "n"): if machine.phase == .open { js("window.perch && window.perch.snoozeMenu(true)") } else { return false }
        case (_, "a"), (_, "d"):
            guard machine.phase == .open, projects.indices.contains(machine.selected),
                  let ask = projects[machine.selected].ask, ask.answerable, ask.kind == .permission else { return false }
            js("window.perch && window.perch.answering('\(ch == "a" ? "allow" : "deny")')")
            answer(ch == "a" ? "allow" : "deny"); return true
        default: return false
        }
        if machine.phase == .open { restartTimer(); push() }
        return true
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

    /// Only a card you asked for takes the keyboard. Hover and Perch speaking up never do, except a card you hovered open
    /// on something to answer: its keys must reach Perch, not the agent's own prompt behind it.
    private var cardTakesKeys: Bool {
        guard !proactiveOpen else { return false }
        guard openedByHover else { return true }
        return machine.phase == .open && projects.indices.contains(machine.selected) && projects[machine.selected].ask?.answerable == true
    }

    // MARK: the pointer. X has no global mouse monitor for an app that is not grabbing, so Perch reads the pointer: 30 times
    // a second near the top of a screen or while a card is up, 4 times a second otherwise.
    private var lastCursor = CGPoint(x: -1, y: -1)
    private var cursorFast = true
    private var buttonsWere: UInt32 = 0
    private var wasKey = false
    private func startPointerPolling() {
        GLoop.every(cursorFast ? 1.0 / 30.0 : 0.25) { [weak self] in
            guard let self else { return false }
            let (at, buttons) = FakeKeys.pointer()
            let top = ScreenChooser.under(at).map { $0.frame.maxY - at.y } ?? 0
            let fast = self.machine.phase != .idle || top < 160 || self.activityMode != ""
            if fast != self.cursorFast { self.cursorFast = fast; self.startPointerPolling(); return false }
            // Presses and releases anywhere, for "a click outside the card closes it": from raw button events when the
            // hotkey thread hears them (a touchpad tap is shorter than a poll), else from the button mask here.
            let down = buttons & 0x700 != 0, wasDown = self.buttonsWere & 0x700 != 0
            self.buttonsWere = buttons
            if !self.hearsButtons {
                if down && !wasDown { self.pressedElsewhere(at) }
                if !down && wasDown { self.releasedElsewhere(at) }
            }
            // Another app took the keyboard from the card.
            let key = self.panel.isKeyWindow
            if self.wasKey && !key { self.makeWay() }
            self.wasKey = key
            self.mouseMoved(at, buttonDown: down)
            self.watchLaunchers()
            if self.machine.phase != .idle || self.activityMode == "full", self.ready, at != self.lastCursor {
                self.lastCursor = at
                let f = self.panel.frame
                self.js("window.perch && window.perch.cursor(\(at.x - f.minX), \(f.maxY - at.y))")
            }
            // Override-redirect windows are stacked by no one: stay above what came up since.
            if self.machine.phase != .idle || self.activityMode != "" { self.panel.raise() }
            return true
        }
    }

    /// Only the card (or the activity) takes clicks; the rest of the panel lets them through to what is behind.
    private func updateClickRect() {
        let r: CGRect
        if machine.phase == .idle { r = activityMode == "full" ? activityRect : .zero } else { r = cardRect }
        let f = panel.frame
        panel.clickRect = CGRect(x: r.minX - f.minX, y: f.maxY - r.maxY, width: r.width, height: r.height).integral
    }

    /// A click anywhere outside the card closes it, as the button comes up. A press that ends on the card (a file dragged
    /// there) keeps it. Not during onboarding.
    private var pressedOutside = false
    private var cardRect: CGRect { NotchGeometry.contentRect(width: contentSize.width, height: contentSize.height, screen: info) }
    /// Raw button events from the hotkey thread (main.swift wires them); when set, the poll leaves presses to them.
    var hearsButtons = false
    func mouseButton(down: Bool) {
        let (at, _) = FakeKeys.pointer()
        if down { pressedElsewhere(at) } else { releasedElsewhere(at) }
    }
    private func pressedElsewhere(_ at: CGPoint) {
        pressedOutside = machine.phase != .idle && !cardRect.contains(at)
    }
    private func releasedElsewhere(_ at: CGPoint) {
        guard pressedOutside else { return }
        pressedOutside = false
        guard machine.phase != .idle, machine.phase != .onboarding, !holdOpen else { return }
        if cardRect.contains(at) { return }   // dropped on the card
        send(.dismiss)
    }

    /// Another app took the keyboard from the card: you have gone elsewhere, so the card makes way. Not during onboarding,
    /// nor while a reply is typed.
    private func makeWay() {
        guard machine.phase != .idle, machine.phase != .onboarding, !holdOpen, !replyOpen else { return }
        if buttonsWere & 0x700 != 0 { return }   // a press elsewhere: the release decides
        send(.dismiss)
    }

    /// A card without the keyboard never hears it go, so while a card is up Perch looks a few times a second for a
    /// launcher that has it. Twice in a row counts.
    private var launcherCheck = (tick: 0, hits: 0)
    private func watchLaunchers() {
        guard machine.phase != .idle else { launcherCheck = (0, 0); return }
        launcherCheck.tick += 1
        guard launcherCheck.tick % 8 == 0 else { return }
        let launcher = Quiet.launcherOpen()
        launcherCheck.hits = launcher == nil ? 0 : launcherCheck.hits + 1
        if launcherCheck.hits >= 2 {
            Trace.log("Perch: \(launcher ?? "") has the keyboard, the card makes way")
            launcherCheck.hits = 0; makeWay()
        }
    }

    /// The top edge plus a little room for the character beside it.
    private func notchHoverRect() -> CGRect {
        NotchGeometry.hoverRect(for: info, wingsWidth: activityMode == "wings" || activityMode == "sent" ? activitySize.width : 0)
    }

    /// Show Perch on is a screen other than the mouse's, so the resting panel waits there. Resting the cursor on the top of
    /// another screen that opens on hover still brings Perch there; leaving that zone sends it back.
    private var awayForHover = false
    private var detourFrom: (screen: Screen, at: Date)?
    /// When the card last closed: for the 700 ms its closing plays, the panel stays where it is.
    private var closedAt = Date.distantPast
    private func followHoverWhileFixed(_ at: CGPoint) {
        guard Date().timeIntervalSince(closedAt) > 0.7 else { return }
        let screens = Screen.screens, frames = screens.map(\.frame)
        if let i = ScreenPicker.index(of: at, in: frames), screens[i] != screen, Prefs.hoverExternal,
           NotchGeometry.hovering(at, frames: frames, index: i, rect: NotchGeometry.hoverRect(for: screens[i].screenInfo)) {
            if detourFrom?.screen != screens[i] { detourFrom = (screens[i], Date()) }
            guard HoverDetour.leave(enteredAt: detourFrom!.at, now: Date(), activityShowing: activityMode != "") else { return }
            detourFrom = nil; awayForHover = true; place(on: screens[i]); push(); return
        }
        detourFrom = nil
        guard awayForHover, hoverTask == nil,
              HoverDetour.goBack(at: at, zone: notchHoverRect(), activity: activityMode == "full" ? activityRect : nil) else { return }
        awayForHover = false
        let home = ScreenChooser.rest()
        if home != screen { place(on: home); push() }
    }

    /// The cursor is at the top edge of the screen it is on, where hovering opens Perch (Settings: hover at the top edge).
    private func overNotch(_ at: CGPoint) -> Bool {
        guard notchHoverRect().contains(at), ScreenChooser.under(at)?.frame == info.frame else { return false }
        return info.notchSize != nil || Prefs.hoverExternal
    }

    /// Resting the cursor at the top edge for a moment opens the welcome card.
    private func hoverIdle(_ at: CGPoint, buttonDown: Bool) {
        let inside = overNotch(at)
        if inside != tabHot { tabHot = inside; js("window.perch && window.perch.hot(\(inside))") }
        if !inside { hoverLatched = false; hoverTask?.cancel(); hoverTask = nil; return }
        if hoverLatched || hoverTask != nil || buttonDown { return }
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled else { return }
            self.hoverTask = nil
            if self.machine.phase == .idle, self.overNotch(Mouse.location), Quiet.launcherOpen() == nil { self.comeBack(byHover: true) }
        }
    }

    private func mouseMoved(_ at: CGPoint, buttonDown: Bool) {
        if machine.phase == .idle {
            if Prefs.showOn == .mouse { if let under = ScreenChooser.under(at), under != screen { place(on: under); push() } }
            else { followHoverWhileFixed(at) }
            // Open, the activity takes clicks (its buttons) and resting on it holds it; it does not open the card.
            let onActivity = activityMode == "full" && activityRect.insetBy(dx: -2, dy: -2).contains(at)
            if panel.ignoresMouseEvents == onActivity { panel.ignoresMouseEvents = !onActivity; updateClickRect() }
            if onActivity {
                hoverTask?.cancel(); hoverTask = nil; hoverLatched = true
                if !tabHot { tabHot = true; js("window.perch && window.perch.hot(true)") }
                return
            }
            hoverIdle(at, buttonDown: buttonDown); return
        }
        let rect = cardRect
        let inside = rect.contains(at)
        panel.ignoresMouseEvents = !inside
        if inside, !pointerOnCard, panel.allowsKey, !panel.isKeyWindow, cardTakesKeys { panel.makeKey() }
        pointerOnCard = inside
        // Writing a reply makes the card yours: it stays when the pointer wanders off, until a click elsewhere or Esc.
        if openedByHover, !replyOpen, Date().timeIntervalSince(openedAt) > 0.5 {
            if rect.insetBy(dx: -10, dy: -10).contains(at) { leftCardAt = nil }
            else if let t = leftCardAt { if Date().timeIntervalSince(t) > 0.25 { leftCardAt = nil; send(.dismiss); return } }
            else { leftCardAt = Date() }
        }
        if inside != machine.hovering {
            send(.hoverChanged(inside))
            if machine.phase == .open { restartTimer(); push() }
        }
        updateClickRect()
    }
}

/// PERCH_TRACE=1 logs what the Mac logs with NSLog under the same switch.
enum Trace {
    static let on = ProcessInfo.processInfo.environment["PERCH_TRACE"] != nil
    static func log(_ s: @autoclosure () -> String, always: Bool = false) {
        guard on || always else { return }
        FileHandle.standardError.write(Data((s() + "\n").utf8))
    }
}

/// Synthetic keys through XTest, for the paste fallback of a reply, and the pointer with its buttons.
@MainActor
enum FakeKeys {
    static func tap(keysym: UInt, ctrl: Bool = false, shift: Bool = false) {
        guard let d = X11.display else { return }
        let code = XKeysymToKeycode(d, KeySym(keysym))
        let ctrlCode = XKeysymToKeycode(d, KeySym(0xffe3)), shiftCode = XKeysymToKeycode(d, KeySym(0xffe1))
        if ctrl { XTestFakeKeyEvent(d, UInt32(ctrlCode), 1, 0) }
        if shift { XTestFakeKeyEvent(d, UInt32(shiftCode), 1, 0) }
        XTestFakeKeyEvent(d, UInt32(code), 1, 0)
        XTestFakeKeyEvent(d, UInt32(code), 0, 0)
        if shift { XTestFakeKeyEvent(d, UInt32(shiftCode), 0, 0) }
        if ctrl { XTestFakeKeyEvent(d, UInt32(ctrlCode), 0, 0) }
        XFlush(d)
    }

    /// The pointer in Cocoa's coordinates, and X's button mask (Button1Mask is 0x100).
    static func pointer() -> (CGPoint, UInt32) {
        guard let d = X11.display else { return (.zero, 0) }
        var r: Window = 0, c: Window = 0, rx: Int32 = 0, ry: Int32 = 0, wx: Int32 = 0, wy: Int32 = 0, mask: UInt32 = 0
        XQueryPointer(d, X11.root, &r, &c, &rx, &ry, &wx, &wy, &mask)
        return (X11.flip(CGPoint(x: Int(rx), y: Int(ry))), mask)
    }
}
