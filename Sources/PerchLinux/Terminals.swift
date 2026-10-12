import CPerchLinux
import Foundation
import PerchCore

// Running agents from /proc (LiveSessions), going back to them, typing into them, opening a new terminal. Apps are named
// by their windows' WM_CLASS, lowercased (X11.appId), where the Mac uses bundle ids. Everything here may run off the main
// thread: X goes through Perch's own connection (XServer), never GDK's.

/// Terminal apps. Pick up goes back to the pane or window a session runs in, or opens it again in the terminal you use.
enum Terminals {
    /// Every app that counts as a terminal (WM_CLASS, lowercased), with the name its icon goes by in the page.
    static let keys: [String: String] = [
        "xfce4-terminal": "xfce4-terminal", "gnome-terminal": "gnome-terminal", "kitty": "kitty", "alacritty": "alacritty",
        "org.wezfurlong.wezterm": "wezterm", "com.mitchellh.ghostty": "ghostty", "ghostty": "ghostty", "konsole": "konsole",
        "xterm": "xterm", "tilix": "tilix", "terminator": "terminator", "code": "vscode", "cursor": "cursor", "zed": "zed",
        "dev.zed.zed": "zed",
    ]
    /// The terminals Perch can open a new session in (the editors are not among them).
    static let opens: Set<String> = Set(TerminalLaunch.binaries.keys)

    /// The terminal you used last, if Perch can open a session in it; else the system's own; else the first one installed.
    static var preferred: String {
        if let last = Prefs.lastTerminal, opens.contains(last), installed(last) { return last }
        return systemDefault ?? order.first(where: installed) ?? "xterm"
    }
    private static let order = ["xfce4-terminal", "gnome-terminal", "konsole", "kitty", "alacritty", "org.wezfurlong.wezterm", "com.mitchellh.ghostty", "tilix", "terminator", "xterm"]
    static func installed(_ app: String) -> Bool { TerminalLaunch.binaries[app].flatMap(Proc.which) != nil }

    /// XFCE's choice (helpers.rc), else $TERMINAL, else Debian's x-terminal-emulator, if it is one Perch can open.
    private static let systemDefault: String? = {
        let env = ProcessInfo.processInfo.environment
        let config = env["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? FileManager.default.homeDirectoryForCurrentUser.path + "/.config"
        let helpers = (try? String(contentsOfFile: config + "/xfce4/helpers.rc", encoding: .utf8)).flatMap(TerminalLaunch.fromHelpersRC)
        let alternative = Proc.which("x-terminal-emulator").map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }.flatMap(TerminalLaunch.app(named:))
        return [helpers, env["TERMINAL"].flatMap(TerminalLaunch.app(named:)), alternative].compactMap { $0 }.first(where: installed)
    }()

    /// Opens a new window in `cwd` running `command` in your shell, which stays open after it.
    static func open(_ command: String, in cwd: String, app: String = preferred) {
        let shell = ProcessInfo.processInfo.environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/bash"
        guard let argv = TerminalLaunch.argv(app: opens.contains(app) ? app : preferred, cwd: cwd, command: command, shell: shell),
              let exe = Proc.which(argv[0]) else { return }
        // The variables Perch set for itself, and those of a multiplexer Perch was started in, stay behind.
        var env = ProcessInfo.processInfo.environment
        for k in env.keys where ["GDK_BACKEND", "WEBKIT_DISABLE_COMPOSITING_MODE", "DESKTOP_STARTUP_ID", "XDG_ACTIVATION_TOKEN", "TMUX", "TMUX_PANE"].contains(k)
            || ["HERDR_", "KITTY_", "WEZTERM_", "CMUX_"].contains(where: k.hasPrefix) { env[k] = nil }
        if !spawn([exe] + argv.dropFirst(), env: env.map { "\($0.key)=\($0.value)" }, cwd: FileManager.default.fileExists(atPath: cwd) ? cwd : nil) {
            NSLog("Perch: could not open \(argv[0])")
        }
    }

    /// Starts a program that lives on its own: GLib forks twice (so nothing is left for Perch to reap) and closes Perch's
    /// descriptors in it, and it gets its own session, so no signal meant for Perch reaches it. Foundation's Process is
    /// not used here: it waits on a socket the terminal would inherit, so it waits until the terminal quits.
    @discardableResult
    static func spawn(_ argv: [String], env: [String], cwd: String?) -> Bool {
        func cStrings(_ a: [String]) -> [UnsafeMutablePointer<CChar>?] { a.map { strdup($0) } + [nil] }
        var args = cStrings(argv), envp = cStrings(env)
        defer { args.forEach { free($0) }; envp.forEach { free($0) } }
        let flags = GSpawnFlags(rawValue: G_SPAWN_STDOUT_TO_DEV_NULL.rawValue | G_SPAWN_STDERR_TO_DEV_NULL.rawValue)   // stdin is /dev/null by default
        return g_spawn_async(cwd, &args, &envp, flags, { _ in _ = setsid() }, nil, nil, nil) != 0
    }

    /// Brings what this session runs in to the front and says which app has it: its herdr pane (in the terminal that shows
    /// herdr), its tmux pane (in the terminal that shows tmux), its kitty or WezTerm tab when they can be asked, else its
    /// terminal's window (picked by title when the terminal has several). Nil when there is nothing to bring forward.
    @discardableResult
    static func focus(_ live: LiveSessions.Hit, hints: [String] = []) -> String? {
        switch live.place {
        case .herdr(let pane, let socket, let session):
            Herdr.focus(pane: pane, socket: socket, bin: live.herdrBin)
            if let v = live.viewer { return show(v) }
            // Nothing shows that server: open herdr in your terminal, on the pane just focused.
            open(Herdr.attach(session: session, bin: live.herdrBin), in: live.cwd)
            return preferred
        case .cmux, .tab:
            if let t = live.tmux {
                if Tmux.focus(t) { return raise(live.term, app: live.app, cwd: live.cwd, hints: hints) ?? live.app }
                // No terminal shows that server: open one on the pane.
                Tmux.select(t)
                open(Tmux.attach(t), in: live.cwd)
                return preferred
            }
            return raise(live.term, app: live.app, cwd: live.cwd, hints: hints)
        }
    }

    /// Brings forward the terminal showing a herdr client.
    static func show(_ v: LiveSessions.Viewer) -> String? {
        if let t = v.tmux { _ = Tmux.focus(t) }
        return raise(v.term, app: v.app, cwd: v.cwd, hints: [])
    }

    /// The terminal's window, raised: the X window kitty says holds the tab, the one WezTerm titles with the pane, else
    /// among that terminal's windows the one whose title names the session or its folder, else the one on top.
    static func raise(_ term: LiveSessions.Term?, app: String?, cwd: String, hints: [String]) -> String? {
        guard let app else { return nil }
        let all = XServer.shared.windows().filter { $0.app == app }
        let mine = term?.pid.map { pid in all.filter { $0.pid == pid } }.flatMap { $0.isEmpty ? nil : $0 } ?? all
        var target: Window?
        if let t = term, let k = t.kitty, let s = t.kittySocket, let w = Kitty.focus(window: k, socket: s) {
            target = all.first { $0.id == Window(w) }?.id
        } else if let t = term, let p = t.wezterm, let title = Wezterm.activate(pane: p, socket: t.weztermSocket) {
            target = mine.last { $0.title == title }?.id
        }
        if target == nil, let top = mine.last {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            target = mine.count == 1 ? top.id : WindowPick.best(mine.map(\.title), cwd: cwd, home: home, hints: hints).map { mine[$0].id } ?? top.id
        }
        if let target { XServer.shared.activate(target) }
        return app
    }

    /// Types a line into what runs this session and presses Return, without bringing it forward or the clipboard: a herdr
    /// or tmux pane exactly, a kitty window or WezTerm pane when they can be asked. False where it cannot, and whenever
    /// something else has the agent's terminal (a shell after it quit, an editor or pager it opened): Return would land there.
    static func type(_ line: String, into live: LiveSessions.Hit) -> Bool {
        if case .herdr(let pane, let socket, _) = live.place { return Herdr.type(line, pane: pane, socket: socket, bin: live.herdrBin) }
        guard Proc.stat(live.pid)?.foreground == true else { return false }
        if let t = live.tmux { return Tmux.type(line, into: t) }
        if let t = live.term, let k = t.kitty, let s = t.kittySocket { return Kitty.type(line, window: k, socket: s) }
        if let t = live.term, let p = t.wezterm { return Wezterm.type(line, pane: p, socket: t.weztermSocket) }
        return false
    }

    /// Runs a command line tool (found on PATH, or given by path) and returns what it printed, or nil when it failed or took
    /// longer than `timeout`. `input` goes to its stdin.
    @discardableResult
    static func tool(_ name: String, _ args: [String], env: [String: String] = [:], input: String? = nil, timeout: TimeInterval = 4) -> String? {
        guard let path = Proc.which(name) else { return nil }
        let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
        if !env.isEmpty { p.environment = ProcessInfo.processInfo.environment.merging(env) { _, new in new } }
        let out = Pipe(), inp = Pipe()
        p.standardOutput = out; p.standardError = FileHandle.nullDevice
        p.standardInput = input == nil ? FileHandle.nullDevice : inp
        do { try p.run() } catch { return nil }
        if let input { inp.fileHandleForWriting.write(Data(input.utf8)); try? inp.fileHandleForWriting.close() }
        final class Box: @unchecked Sendable { var data = Data() }
        let box = Box(), done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { box.data = out.fileHandleForReading.readDataToEndOfFile(); done.signal() }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            kill(p.processIdentifier, SIGKILL)
            if done.wait(timeout: .now() + 1) == .timedOut { return nil }   // something it started still holds the pipe
        }
        p.waitUntilExit()
        if ProcessInfo.processInfo.environment["PERCH_TRACE"] != nil { NSLog("Perch: \(name) \(args.joined(separator: " ")) -> \(p.terminationStatus)") }
        return p.terminationStatus == 0 && p.terminationReason == .exit ? String(decoding: box.data, as: UTF8.self) : nil
    }

    static func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}

/// Coding agents running right now in a terminal, a herdr pane or a tmux pane, found from /proc and their own
/// environment. No permission needed.
enum LiveSessions {
    struct Hit: Equatable {
        let pid: pid_t, cwd: String, tty: String
        /// An Agent id.
        let agent: String
        /// The terminal app it shows in (an app id). For herdr and tmux, the terminal that shows a client of its server.
        let app: String?
        let place: Place
        let argv: [String]
        let started: Date
        /// herdr: the client attached to its server, which is where you see it. Nil when none is attached.
        let viewer: Viewer?
        /// herdr: the CLI the pane names (HERDR_BIN_PATH).
        let herdrBin: String?
        /// Where it shows in its terminal app.
        var term: Term? = nil
        /// tmux: its pane, and the client that shows it.
        var tmux: Tmux.Pane? = nil
    }
    /// A herdr client in a terminal: what shows a herdr server's panes.
    struct Viewer: Equatable {
        let pid: pid_t; let tty: String; let cwd: String; let app: String?; let place: Place; let session: String
        var term: Term? = nil
        var tmux: Tmux.Pane? = nil
    }
    /// Where a process shows inside its terminal app, so that window (and tab, where the terminal can be asked) comes forward.
    struct Term: Equatable {
        /// The terminal's process, the owner of its X windows. Nil when it was not found.
        var pid: pid_t?
        /// The terminal's own tty there: the process's, or for one in tmux, the tmux client's.
        var tty: String
        /// kitty: the window ($KITTY_WINDOW_ID) and the socket it listens on ($KITTY_LISTEN_ON), when it does.
        var kitty: String? = nil, kittySocket: String? = nil
        /// WezTerm: the pane ($WEZTERM_PANE) and its socket ($WEZTERM_UNIX_SOCKET).
        var wezterm: String? = nil, weztermSocket: String? = nil
    }

    /// Agent processes that have a terminal. Ones started without one are left out.
    static func all() -> [Hit] { scan().hits }

    /// The agents, and the herdr clients attached right now.
    static func scan() -> (hits: [Hit], viewers: [Viewer]) {
        var ctx = Context()
        var found: [(pid: pid_t, agent: Agent, args: ProcessArgs, tty: String, cwd: String, stat: ProcStat)] = []
        var viewers: [Viewer] = []
        let interesting: Set<String> = ["claude", "codex", "opencode", "pi", "node", "bun", "herdr"]
        for (pid, st) in ctx.table where st.ttyNr != 0 {
            guard let tty = st.tty, let exe = Proc.exe(pid) else { continue }
            let name = (exe as NSString).lastPathComponent
            guard interesting.contains(name) || name.hasPrefix("codex-") || exe.contains("/claude/versions/") else { continue }
            let args = Proc.args(pid, executable: exe) ?? ProcessArgs(executable: exe, argv: [], environment: [:])
            let cwd = Proc.cwd(pid) ?? ""
            if name == "herdr" {
                // A client: `herdr`, `herdr --session x`, `herdr session attach x`. The server runs without a terminal.
                guard !args.argv.contains("server"), !args.argv.contains("--remote") else { continue }
                let session = value(after: "--session", in: args.argv) ?? (args.argv.count >= 4 && args.argv[1] == "session" && args.argv[2] == "attach" ? args.argv[3] : "default")
                let place = Place.from(environment: args.environment), at = ctx.shows(st, env: args.environment, tty: tty, place: place)
                viewers.append(Viewer(pid: pid, tty: tty, cwd: cwd, app: at.app, place: place, session: session, term: at.term, tmux: at.tmux))
                continue
            }
            guard let agent = Agent.recognise(executable: exe, argv0: args.argv.first) else { continue }
            found.append((pid, agent, args, tty, cwd, st))
        }
        let hits = found.sorted { $0.pid < $1.pid }.map { f in
            let place = Place.from(environment: f.args.environment)
            var viewer: Viewer?, app: String?, term: Term?, tmux: Tmux.Pane?
            if case .herdr(_, _, let session) = place {
                viewer = viewers.first { $0.session == session }
                app = viewer?.app; term = viewer?.term
            } else {
                (app, term, tmux) = ctx.shows(f.stat, env: f.args.environment, tty: f.tty, place: place)
            }
            return Hit(pid: f.pid, cwd: f.cwd, tty: f.tty, agent: f.agent.id, app: app, place: place, argv: f.args.argv, started: Proc.started(f.stat),
                       viewer: viewer, herdrBin: f.args.environment["HERDR_BIN_PATH"], term: term, tmux: tmux)
        }
        return (hits, viewers)
    }

    /// A process's parent.
    static func parent(of pid: pid_t) -> pid_t? { Proc.stat(pid)?.ppid }

    private static func value(after flag: String, in argv: [String]) -> String? {
        guard let i = argv.firstIndex(of: flag), argv.indices.contains(i + 1) else { return nil }
        return argv[i + 1]
    }

    /// One scan's view of the process table, the windows and the tmux servers, each read once.
    private struct Context {
        let table = Proc.table()
        /// Each process that has windows, and their app.
        let owners: [pid_t: String] = {
            var o: [pid_t: String] = [:]
            for w in XServer.shared.windows() { if let p = w.pid, let a = w.app, o[p] == nil { o[p] = a } }
            return o
        }()
        var tmux: [String: (clients: [TmuxList.Client], panes: [TmuxList.Pane])] = [:]

        /// Where a process with a terminal shows. In a tmux pane ($TMUX and $TMUX_PANE, and that pane's tty is its own: a
        /// terminal started from tmux passes them on to what runs in it), the terminal of the client that shows its session;
        /// otherwise the terminal up its parent chain.
        mutating func shows(_ st: ProcStat, env: [String: String], tty: String, place: Place) -> (app: String?, term: Term?, tmux: Tmux.Pane?) {
            if place == .tab, let socket = TmuxList.socket(fromEnv: env["TMUX"]), let id = env["TMUX_PANE"] {
                if tmux[socket] == nil { tmux[socket] = (Tmux.clients(socket), Tmux.panes(socket)) }
                let server = tmux[socket]!
                if let pane = server.panes.first(where: { $0.id == id && $0.tty == tty }) {
                    let client = TmuxList.client(for: pane.session, in: server.clients)
                    var app: String?, term: Term?
                    if let c = client, let cst = table[c.pid] {
                        let t = terminal(above: cst.ppid)
                        app = t?.app
                        let cenv = Proc.exe(c.pid).flatMap { Proc.args(c.pid, executable: $0)?.environment } ?? [:]
                        term = Self.term(env: cenv, tty: c.tty, at: t)
                    }
                    return (app, term, Tmux.Pane(socket: socket, pane: id, session: pane.session, client: client?.tty))
                }
            }
            let t = terminal(above: st.ppid)
            return (t?.app, Self.term(env: env, tty: tty, at: t), nil)
        }

        /// The first process up the chain that has windows: the terminal (or editor) the shell lives in. Without windows to
        /// go by (no X server), a terminal known by its program's name.
        func terminal(above start: pid_t) -> (pid: pid_t, app: String)? {
            var chain: [pid_t] = [], pid = start
            for _ in 0..<16 where pid > 1 {
                chain.append(pid)
                guard let up = table[pid]?.ppid else { break }
                pid = up
            }
            if let p = chain.first(where: { owners[$0] != nil }) { return (p, owners[p]!) }
            for p in chain { if let app = Proc.exe(p).flatMap({ byName[($0 as NSString).lastPathComponent] }) { return (p, app) } }
            return nil
        }

        /// What kitty and WezTerm tell their processes about the window or pane they run in, when it is the terminal found.
        static func term(env: [String: String], tty: String, at t: (pid: pid_t, app: String)?) -> Term {
            var term = Term(pid: t?.pid, tty: tty)
            if t?.app == "kitty", let w = env["KITTY_WINDOW_ID"], env["KITTY_PID"].map({ pid_t($0) == t?.pid }) ?? true {
                term.kitty = w; term.kittySocket = env["KITTY_LISTEN_ON"].flatMap { $0.isEmpty ? nil : $0 }
            }
            if t?.app == "org.wezfurlong.wezterm", let p = env["WEZTERM_PANE"] {
                term.wezterm = p; term.weztermSocket = env["WEZTERM_UNIX_SOCKET"].flatMap { $0.isEmpty ? nil : $0 }
            }
            return term
        }

        private let byName: [String: String] = [
            "xfce4-terminal": "xfce4-terminal", "gnome-terminal-server": "gnome-terminal", "kitty": "kitty", "alacritty": "alacritty",
            "wezterm-gui": "org.wezfurlong.wezterm", "ghostty": "com.mitchellh.ghostty", "konsole": "konsole", "xterm": "xterm", "tilix": "tilix",
            "code": "code", "cursor": "cursor", "zed-editor": "zed",
        ]
    }
}
