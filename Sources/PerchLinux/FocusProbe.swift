import CPerchLinux
import Foundation
import PerchCore

/// Reads what is in front of you in the terminal you are using: which tty its active window shows, and inside it the tmux
/// pane or herdr pane in front. kitty and WezTerm can be asked which tab is in front; any other terminal only when the
/// window's process runs a single tty, since xfce4-terminal, GNOME Terminal and the like keep every tab of every window
/// in one process and have no way to be asked. It reads off the main thread, a second apart at most, and a reading older
/// than a few seconds is not trusted: then every live session in that app counts as "maybe" (see `Focus`).
@MainActor
final class FocusProbe {
    struct Reading {
        let app: String
        let at: Date
        let looking: Looking
    }
    private(set) var reading: Reading?
    private var busy = false
    /// Called on the main thread when a new reading says something different from the last.
    var changed: (() -> Void)?

    /// Where the agents and herdr clients were last seen running (RealSessionProvider's scan).
    nonisolated(unsafe) private static var known: (hits: [LiveSessions.Hit], viewers: [LiveSessions.Viewer]) = ([], [])
    private nonisolated static let lock = NSLock()
    nonisolated static func setKnown(_ v: (hits: [LiveSessions.Hit], viewers: [LiveSessions.Viewer])) { lock.lock(); known = v; lock.unlock() }
    private nonisolated static func getKnown() -> (hits: [LiveSessions.Hit], viewers: [LiveSessions.Viewer]) { lock.lock(); defer { lock.unlock() }; return known }

    /// A reading older than this is not trusted. While nothing changes it is read every 2 s, so it stays inside this.
    static let maxAge: TimeInterval = 5
    private var lastChange = Date.distantPast

    /// Apps this can read: the terminals. Editors (VS Code, Cursor, Zed) show their terminal beside files, so a single tty
    /// there does not mean you are looking at it.
    static func reads(_ app: String) -> Bool { Terminals.keys[app] != nil && !["code", "cursor", "zed", "dev.zed.zed"].contains(app) }

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
            let r = Reading(app: app, at: Date(), looking: Self.looking(in: app))
            await MainActor.run {
                self.busy = false
                let moved = self.reading.map { $0.app != r.app || $0.looking != r.looking } ?? true
                self.reading = r
                if moved { self.lastChange = Date(); self.changed?() }
            }
        }
    }

    /// What is in front inside a terminal app. `cannotTell` when it cannot be read.
    nonisolated static func looking(in app: String) -> Looking {
        let known = getKnown()
        guard let active = XServer.shared.active(), let win = XServer.shared.windows().first(where: { $0.id == active }),
              win.app == app, let pid = win.pid, let tty = shownTty(win: win, pid: pid, known: known) else { return .cannotTell }
        var spots: Set<String> = [Spot.tty(tty)]
        // A tmux client there: its session's active pane is what you see.
        let sockets = Set((known.hits.compactMap(\.tmux) + known.viewers.compactMap(\.tmux)).map(\.socket))
        for socket in sockets {
            for c in Tmux.clients(socket) where c.tty == tty { spots.insert(Spot.tty(c.paneTty)) }
        }
        // A herdr client there: the panes are what you are looking at, and herdr says which has focus.
        let viewers = known.viewers.filter { $0.tty == tty || $0.term?.tty == tty || spots.contains(Spot.tty($0.tty)) }
        var servers = Set<String>()
        for session in Set(viewers.map(\.session)) {
            let sockets = Set(known.hits.compactMap { h -> String? in if case .herdr(_, let s, let name) = h.place, name == session { return s } else { return nil } })
            let clients = known.viewers.filter { $0.session == session }.count
            for socket in sockets {
                if clients == 1, let pane = Herdr.focusedPane(socket: socket, bin: known.hits.first { if case .herdr(_, let s, _) = $0.place { return s == socket } else { return false } }?.herdrBin) {
                    spots.insert(Spot.herdr(socket: socket, pane: pane))
                } else { servers.insert(socket) }
            }
        }
        return Looking(spots: spots, servers: servers)
    }

    /// The tty the active window shows: the tab kitty or WezTerm has in front there, else the terminal's one tty when its
    /// process runs only one (every window of it, every tab), else nil.
    nonisolated private static func shownTty(win: XServer.Win, pid: pid_t, known: (hits: [LiveSessions.Hit], viewers: [LiveSessions.Viewer])) -> String? {
        let terms = known.hits.compactMap(\.term) + known.viewers.compactMap(\.term)
        if win.app == "kitty", let socket = terms.first(where: { $0.pid == pid && $0.kittySocket != nil })?.kittySocket {
            if let front = Kitty.frontPid(socket: socket, platformWindow: UInt(win.id)), let tty = Proc.stat(front)?.tty { return tty }
        }
        if win.app == "org.wezfurlong.wezterm", let socket = terms.first(where: { $0.pid == pid && $0.weztermSocket != nil })?.weztermSocket,
           let tty = Wezterm.focusedTty(socket: socket) { return tty }
        let ttys = Set(Proc.table().values.filter { $0.ppid == pid }.compactMap(\.tty))
        return ttys.count == 1 ? ttys.first : nil
    }
}

/// The app in front: the active window's app id, else nil.
enum FrontApp {
    static func id() -> String? { XServer.shared.active().flatMap { a in XServer.shared.windows().first { $0.id == a }?.app } }
}
