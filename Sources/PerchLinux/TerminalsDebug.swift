import CPerchLinux
import Foundation
import PerchCore

/// `--terminals <command>`: tries the processes-and-terminals pieces by hand, without the panel.
///   scan                      the agents and herdr clients found, and where each shows
///   front                     the app in front and what FocusProbe reads there
///   focus <pid> [hint...]     Pick up's way back to that agent
///   type <pid> <line>         a reply typed into it
///   open <app> <cwd> <cmd>    a new terminal window
///   files                     the files on the clipboard, as paths
///   clip <text>               the clipboard: what was there, set, then put back (serving it for 3 s each way)
enum TerminalsDebug {
    @MainActor
    static func handle(_ args: [String]) -> Bool {
        guard let i = args.firstIndex(of: "--terminals") else { return false }
        let a = Array(args.dropFirst(i + 1))
        switch a.first ?? "scan" {
        case "scan":
            let (hits, viewers) = LiveSessions.scan()
            for h in hits {
                print("agent \(h.agent) pid \(h.pid) tty \(h.tty) cwd \(h.cwd) app \(h.app ?? "-") place \(h.place) spot \(Spot.key(h.place, tty: h.tty))")
                print("   argv \(h.argv) started \(h.started)")
                if let t = h.term { print("   term pid \(t.pid.map(String.init) ?? "-") tty \(t.tty) kitty \(t.kitty ?? "-")@\(t.kittySocket ?? "-") wezterm \(t.wezterm ?? "-")") }
                if let t = h.tmux { print("   tmux \(t.pane) session \(t.session) on \(t.socket) client \(t.client ?? "none")") }
                if let v = h.viewer { print("   herdr viewer pid \(v.pid) tty \(v.tty) app \(v.app ?? "-")") }
            }
            for v in viewers { print("herdr client pid \(v.pid) session \(v.session) tty \(v.tty) app \(v.app ?? "-")") }
            print("preferred \(Terminals.preferred); installed \(Terminals.opens.filter(Terminals.installed).sorted())")
        case "front":
            let app = FrontApp.id() ?? "-"
            FocusProbe.setKnown(LiveSessions.scan())
            print("front \(app) reads \(FocusProbe.reads(app)) looking \(FocusProbe.reads(app) ? FocusProbe.looking(in: app) : .cannotTell)")
        case "focus" where a.count >= 2:
            guard let hit = LiveSessions.all().first(where: { String($0.pid) == a[1] }) else { print("no agent with pid \(a[1])"); return true }
            print("focus -> \(Terminals.focus(hit, hints: Array(a.dropFirst(2))) ?? "nil")")
            usleep(300_000)
            print("now front \(FrontApp.id() ?? "-"): \(XServer.shared.active().flatMap { a in XServer.shared.windows().first { $0.id == a }?.title } ?? "-")")
        case "type" where a.count >= 3:
            guard let hit = LiveSessions.all().first(where: { String($0.pid) == a[1] }) else { print("no agent with pid \(a[1])"); return true }
            print("typed \(Terminals.type(a[2], into: hit))")
        case "open" where a.count >= 4:
            Terminals.open(a[3], in: a[2], app: a[1])
            print("opened")
        case "clip" where a.count >= 2:
            let saved = Clipboard.save()
            print("saved \(saved.map { "\"\($0.prefix(60))\" (\($0.count) chars)" } ?? "nil")")
            Clipboard.set(a[1])
            serve(3)
            Clipboard.restore(saved)
            print("restored")
            serve(3)
        case "files":
            serve(0.5)   // GDK learns what the clipboard offers a moment after it starts
            var got: [String]?
            let offered = Clipboard.filePaths { got = $0 }
            print("files offered \(offered)")
            let end = Date().addingTimeInterval(3)
            while offered, got == nil, Date() < end { g_main_context_iteration(nil, 0); usleep(10_000) }
            print("paths \(got ?? [])")
        default:
            print("perch --terminals scan | front | focus <pid> [hint...] | type <pid> <line> | open <app> <cwd> <cmd> | clip <text>")
        }
        return true
    }

    /// Runs GLib's loop for a while, so the clipboard Perch owns can be read by others.
    private static func serve(_ seconds: Double) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { g_main_context_iteration(nil, 0); usleep(10_000) }
    }
}
