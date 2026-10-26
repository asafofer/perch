import AppKit
import PerchCore

/// Reads what is in front of you in the app you are using: the focused cmux surface or agterm pane, the front Terminal or iTerm2 tab, the
/// Ghostty terminal's folder, the pane herdr has focused or a tmux client shows, the session the Claude app shows.
/// AppleScript and Accessibility are slow and may ask for permission, so it reads off the main thread, a second apart at
/// most, and a reading older than a few seconds is not trusted: then every live session in that app counts as "maybe"
/// (see `Focus`).
@MainActor
final class FocusProbe {
    struct Reading {
        let app: String
        let at: Date
        let looking: Looking
        /// The Claude app and Conductor: what their window shows (a session, a workspace).
        let claude: ClaudeComposer.Showing
    }
    private(set) var reading: Reading?
    private var busy = false
    /// Called on the main thread when a new reading says something different from the last.
    var changed: (() -> Void)?

    /// Where the agents and herdr clients were last seen running (RealSessionProvider.placeTerminalSessions).
    nonisolated(unsafe) static var known: (hits: [LiveSessions.Hit], viewers: [LiveSessions.Viewer]) = ([], [])
    private nonisolated static let lock = NSLock()
    nonisolated static func setKnown(_ v: (hits: [LiveSessions.Hit], viewers: [LiveSessions.Viewer])) { lock.lock(); known = v; lock.unlock() }
    private nonisolated static func getKnown() -> (hits: [LiveSessions.Hit], viewers: [LiveSessions.Viewer]) { lock.lock(); defer { lock.unlock() }; return known }

    /// A reading older than this is not trusted. While nothing changes it is read every 2 s, so it stays inside this.
    static let maxAge: TimeInterval = 5
    private var lastChange = Date.distantPast
    /// Apps this can read. Other terminals and editors cannot be told apart by tab.
    static func reads(_ bid: String) -> Bool {
        bid == Restorer.claudeApp || bid == Restorer.conductorApp || [Terminals.terminal, Terminals.iterm, Terminals.ghostty, Terminals.cmux, "com.cmuxterm.app.nightly", Terminals.agterm].contains(bid)
    }

    /// The last reading of `app`, if it is recent enough to trust.
    func fresh(for app: String) -> Reading? {
        guard let r = reading, r.app == app, Date().timeIntervalSince(r.at) <= Self.maxAge else { return nil }
        return r
    }

    /// The timer's call: reads every second after a change (or a switch of apps), every 2 s once things have been still for 10 s.
    func tick(app: String) {
        let still = Date().timeIntervalSince(lastChange) > 10, age = reading.map { Date().timeIntervalSince($0.at) } ?? .infinity
        if still, reading?.app == app, age < 2 { return }
        poll(app: app)
    }

    /// Reads `app` now in the background, unless a reading is on its way.
    func poll(app: String) {
        guard Self.reads(app), !busy else { return }
        busy = true
        Task.detached(priority: .utility) {
            let r = Self.read(app)
            await MainActor.run {
                self.busy = false
                let moved = self.reading.map { $0.app != r.app || $0.looking != r.looking || $0.claude != r.claude } ?? true
                self.reading = r
                if moved { self.lastChange = Date(); self.changed?() }
            }
        }
    }

    nonisolated private static func read(_ app: String) -> Reading {
        let now = Date()
        if app == Restorer.claudeApp { return Reading(app: app, at: now, looking: .cannotTell, claude: ClaudeComposer.showingNow()) }
        if app == Restorer.conductorApp { return Reading(app: app, at: now, looking: .cannotTell, claude: ConductorApp.showingNow()) }
        return Reading(app: app, at: now, looking: looking(in: app), claude: .unreadable)
    }

    /// What is in front inside a terminal app. `cannotTell` when the app does not answer.
    nonisolated private static func looking(in app: String) -> Looking {
        let known = getKnown()
        func ask(_ source: String) -> String? { Terminals.run(source, quiet: true).flatMap { $0.isEmpty ? nil : $0 } }
        var spots = Set<String>(), viewers: [LiveSessions.Viewer] = []
        switch app {
        case Terminals.terminal:
            guard let tty = ask(#"tell application "Terminal" to return tty of selected tab of front window"#) else { return .cannotTell }
            spots.insert(Spot.tty(tty)); viewers = known.viewers.filter { $0.tty == tty }
        case Terminals.iterm:
            guard let tty = ask(#"tell application "iTerm2" to return tty of current session of current tab of current window"#) else { return .cannotTell }
            spots.insert(Spot.tty(tty)); viewers = known.viewers.filter { $0.tty == tty }
        case Terminals.cmux, "com.cmuxterm.app.nightly":
            let name = app == Terminals.cmux ? "cmux" : "cmux NIGHTLY"
            guard let surface = ask(#"tell application "\#(name)" to return id of focused terminal of selected tab of window 1"#) else { return .cannotTell }
            spots.insert(Spot.cmux(surface: surface))
            viewers = known.viewers.filter { if case .cmux(_, let s) = $0.place { return s.lowercased() == surface.lowercased() } else { return false } }
        case Terminals.agterm:
            guard let pane = Agterm.focusedPane() else { return .cannotTell }
            spots.insert(Spot.agterm(pane: pane))
            viewers = known.viewers.filter { if case .agterm(_, _, let p) = $0.place { return p.lowercased() == pane.lowercased() } else { return false } }
        case Terminals.ghostty:
            // Ghostty has no tty to read: its terminal's folder is matched to the agents and herdr or tmux clients running there. Nothing
            // matches when you are in a shell, or when Perch sees the folder differently; then it cannot tell.
            guard let folder = ask(#"tell application "Ghostty" to return working directory of focused terminal of selected tab of front window"#) else { return .cannotTell }
            // An agent in tmux is told by the pane its client shows, below, not by its folder.
            let here = known.hits.filter { if case .tmux = $0.place { return false }; return $0.app == Terminals.ghostty && $0.cwd == folder }
            spots.formUnion(here.map { Spot.key($0.place, tty: $0.tty) })
            viewers = known.viewers.filter { $0.app == Terminals.ghostty && $0.cwd == folder }
            if here.isEmpty && viewers.isEmpty { return .cannotTell }
        default: return .cannotTell
        }
        // A tmux client in that tab shows one pane, and tmux says which. Unreadable, every session in that app is a maybe.
        for v in viewers {
            guard let socket = v.tmux else { continue }
            guard let pane = Tmux.showing(client: v.tty, socket: socket, bin: v.bin) else { return .cannotTell }
            spots.insert(Spot.tmux(socket: socket, pane: pane))
        }
        // A herdr client in that tab: the panes are what you are looking at, and herdr says which has focus.
        var servers = Set<String>()
        for session in Set(viewers.filter { $0.tmux == nil }.map(\.session)) {
            let sockets = Set(known.hits.compactMap { h -> String? in if case .herdr(_, let s, let name) = h.place, name == session { return s } else { return nil } })
            let clients = known.viewers.filter { $0.tmux == nil && $0.session == session }.count
            for socket in sockets {
                if clients == 1, let pane = Herdr.focusedPane(socket: socket, bin: known.hits.first { if case .herdr(_, let s, _) = $0.place { return s == socket } else { return false } }?.bin) {
                    spots.insert(Spot.herdr(socket: socket, pane: pane))
                } else { servers.insert(socket) }
            }
        }
        return Looking(spots: spots, servers: servers)
    }
}
