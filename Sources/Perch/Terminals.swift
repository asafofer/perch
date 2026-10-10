import AppKit
import Darwin
import PerchCore

/// Terminal apps. Pick up goes back to the tab a session runs in, or opens it again in the terminal you use.
enum Terminals {
    static let terminal = "com.apple.Terminal", iterm = "com.googlecode.iterm2", ghostty = "com.mitchellh.ghostty", cmux = "com.cmuxterm.app"
    /// Every app that counts as a terminal, with the name its icon goes by in the page.
    static let keys: [String: String] = [
        terminal: "terminal", iterm: "iterm", ghostty: "ghostty", cmux: "cmux", "com.cmuxterm.app.nightly": "cmux", "dev.warp.Warp-Stable": "warp",
        "com.github.wez.wezterm": "wezterm", "net.kovidgoyal.kitty": "kitty", "com.microsoft.VSCode": "vscode",
        "com.todesktop.230313mzl4w4u92": "cursor", "dev.zed.Zed": "zed",
    ]
    /// The ones Perch can open a new session in.
    static let opens: Set<String> = [terminal, iterm, ghostty, cmux]

    /// The terminal you used last, if Perch can open a session in it; Terminal otherwise.
    static var preferred: String { Prefs.lastTerminal.flatMap { opens.contains($0) ? $0 : nil } ?? terminal }

    /// Opens a new window (a workspace in cmux) in `cwd` that runs `command`.
    static func open(_ command: String, in cwd: String, app: String = preferred) {
        let typed = "cd \(shellQuote(cwd)) && \(command)"
        switch app {
        case iterm:
            run("""
            tell application "iTerm2"
              activate
              set w to (create window with default profile)
              tell current session of w to write text \(appleQuote(typed))
            end tell
            """)
        case ghostty:
            run("""
            tell application "Ghostty"
              activate
              set cfg to new surface configuration
              set initial working directory of cfg to \(appleQuote(cwd))
              set initial input of cfg to \(appleQuote(command + "\n"))
              new window with configuration cfg
            end tell
            """)
        case cmux:
            Cmux.open(command, in: cwd)
        default:
            run("tell application \"Terminal\"\nactivate\ndo script \(appleQuote(typed))\nend tell")
        }
    }

    /// Brings what this session runs in to the front and says which app has it: its herdr pane (in the terminal that shows
    /// herdr), its cmux surface, or its terminal tab (Terminal and iTerm2 by tty, Ghostty by folder; any other terminal is
    /// brought forward as a whole). Nil when there is nothing to bring forward.
    @discardableResult
    static func focus(_ live: LiveSessions.Hit) -> String? {
        switch live.place {
        case .herdr(let pane, let socket, let session):
            Herdr.focus(pane: pane, socket: socket, bin: live.herdrBin)
            if let v = live.viewer { return show(v) }
            // Nothing shows that server: open herdr in your terminal, on the pane just focused.
            open(Herdr.attach(session: session, bin: live.herdrBin), in: live.cwd)
            return preferred
        case .cmux(let workspace, let surface):
            if Cmux.focus(workspace: workspace, surface: surface) { return cmux }
            return focusTab(app: live.app, tty: live.tty, cwd: live.cwd)
        case .tab:
            return focusTab(app: live.app, tty: live.tty, cwd: live.cwd)
        }
    }

    /// The terminal showing a herdr client, brought forward at that client's tab.
    static func show(_ v: LiveSessions.Viewer) -> String? {
        if case .cmux(let w, let s) = v.place, Cmux.focus(workspace: w, surface: s) { return cmux }
        return focusTab(app: v.app, tty: v.tty, cwd: v.cwd)
    }

    static func focusTab(app: String?, tty: String, cwd: String) -> String? {
        let tty = appleQuote(tty), cwd = appleQuote(cwd)
        let byFolder = { (name: String) in """
            tell application "\(name)"
              set hits to (every terminal whose working directory is \(cwd))
              if (count of hits) is 0 then return "no"
              focus item 1 of hits
              activate
              return "ok"
            end tell
            """ }
        let scripts: [String: String] = [
            terminal: """
            tell application "Terminal"
              repeat with w in windows
                repeat with t in tabs of w
                  if tty of t is \(tty) then
                    set selected of t to true
                    set index of w to 1
                    activate
                    return "ok"
                  end if
                end repeat
              end repeat
            end tell
            """,
            iterm: """
            tell application "iTerm2"
              repeat with w in windows
                repeat with t in tabs of w
                  repeat with s in sessions of t
                    if tty of s is \(tty) then
                      select w
                      select t
                      select s
                      activate
                      return "ok"
                    end if
                  end repeat
                end repeat
              end repeat
            end tell
            """,
            ghostty: byFolder("Ghostty"),
            cmux: byFolder("cmux"),
        ]
        guard let app else { return nil }
        if let script = scripts[app], run(script) == "ok" { return app }
        // No way to pick the tab: bring its terminal forward, which is most of the way there.
        NSRunningApplication.runningApplications(withBundleIdentifier: app).first?.activate()
        return app
    }

    /// Types a line into what runs this session and presses Return, without bringing it forward, the clipboard or
    /// Accessibility: a herdr pane or cmux surface exactly, Terminal and iTerm2 by tty, Ghostty by folder. False where it cannot.
    static func type(_ line: String, into live: LiveSessions.Hit) -> Bool {
        switch live.place {
        case .herdr(let pane, let socket, _): return Herdr.type(line, pane: pane, socket: socket, bin: live.herdrBin)
        case .cmux(let w, let s): if Cmux.type(line, workspace: w, surface: s) { return true }
        case .tab: break
        }
        let text = appleQuote(line), tty = appleQuote(live.tty), cwd = appleQuote(live.cwd)
        let script: String
        switch live.app {
        case terminal:
            script = """
            tell application "Terminal"
              repeat with w in windows
                repeat with t in tabs of w
                  if tty of t is \(tty) then
                    do script \(text) in t
                    return "ok"
                  end if
                end repeat
              end repeat
            end tell
            """
        case iterm:
            script = """
            tell application "iTerm2"
              repeat with w in windows
                repeat with t in tabs of w
                  repeat with s in sessions of t
                    if tty of s is \(tty) then
                      tell s to write text \(text)
                      return "ok"
                    end if
                  end repeat
                end repeat
              end repeat
            end tell
            """
        case ghostty, cmux:
            let name = live.app == ghostty ? "Ghostty" : "cmux"
            script = """
            tell application "\(name)"
              set hits to (every terminal whose working directory is \(cwd))
              if (count of hits) is 0 then return "no"
              input text \(appleQuote(line + "\r")) to item 1 of hits
              return "ok"
            end tell
            """
        default: return false
        }
        return run(script) == "ok"
    }

    /// Runs AppleScript and returns its result, or nil when it fails (not installed, permission refused).
    /// It blocks while macOS asks for Automation permission, so call it off the main thread.
    @discardableResult
    static func run(_ source: String) -> String? {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript"); p.arguments = ["-e", source]
        let out = Pipe(), err = Pipe(); p.standardOutput = out; p.standardError = err
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            NSLog("Perch: AppleScript failed: \(String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")"); return nil
        }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Runs a command line tool and returns what it printed, or nil when it failed.
    @discardableResult
    static func tool(_ path: String, _ args: [String], env: [String: String] = [:]) -> String? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
        if !env.isEmpty { p.environment = ProcessInfo.processInfo.environment.merging(env) { _, new in new } }
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        if ProcessInfo.processInfo.environment["PERCH_TRACE"] != nil { NSLog("Perch: \((path as NSString).lastPathComponent) \(args.joined(separator: " ")) -> \(p.terminationStatus)") }
        return p.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }

    static func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static func appleQuote(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
}

/// herdr, a multiplexer whose server outlives the terminal: its CLI focuses a pane, types into it and opens tabs.
enum Herdr {
    /// The CLI: the one the pane says it came with (HERDR_BIN_PATH), else the usual places.
    static func bin(_ hint: String?) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ([hint].compactMap { $0 } + ["/opt/homebrew/bin/herdr", "/usr/local/bin/herdr", home + "/.local/bin/herdr", home + "/.cargo/bin/herdr"])
            .first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/opt/homebrew/bin/herdr"
    }
    private static func cli(_ args: [String], socket: String, bin hint: String?) -> [String: Any]? {
        guard let out = Terminals.tool(bin(hint), args, env: ["HERDR_SOCKET_PATH": socket]) else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [String: Any]
    }

    /// Shows the pane in every client attached to that server.
    @discardableResult
    static func focus(pane: String, socket: String, bin: String?) -> Bool {
        if cli(["agent", "focus", pane], socket: socket, bin: bin) != nil { return true }
        // Not an agent herdr recognises: show its tab.
        guard let r = cli(["pane", "get", pane], socket: socket, bin: bin)?["result"] as? [String: Any],
              let tab = (r["pane"] as? [String: Any])?["tab_id"] as? String else { return false }
        return cli(["tab", "focus", tab], socket: socket, bin: bin) != nil
    }

    /// Types a line into the pane and presses Return: as a prompt to the agent there, else as raw text.
    static func type(_ line: String, pane: String, socket: String, bin: String?) -> Bool {
        if cli(["agent", "prompt", pane, line], socket: socket, bin: bin) != nil { return true }
        guard cli(["pane", "send-text", pane, line], socket: socket, bin: bin) != nil else { return false }
        return cli(["pane", "send-keys", pane, "enter"], socket: socket, bin: bin) != nil
    }

    /// The command that attaches to a server in a terminal.
    static func attach(session: String, bin: String?) -> String {
        let b = Terminals.shellQuote(Self.bin(bin))
        return session == "default" ? b : "\(b) --session \(Terminals.shellQuote(session))"
    }

    /// Whether a server answers on that socket.
    static func running(socket: String, bin: String?) -> Bool {
        FileManager.default.fileExists(atPath: socket) && cli(["workspace", "list"], socket: socket, bin: bin) != nil
    }

    /// A new tab in that workspace (or a new workspace if it is gone) that runs `command` in `cwd`, focused.
    @discardableResult
    static func run(_ command: String, cwd: String, workspace: String?, socket: String, bin: String?) -> Bool {
        var made = workspace.flatMap { cli(["tab", "create", "--workspace", $0, "--cwd", cwd, "--focus"], socket: socket, bin: bin) }
        if made == nil { made = cli(["workspace", "create", "--cwd", cwd, "--focus"], socket: socket, bin: bin) }
        guard let r = made?["result"] as? [String: Any], let pane = (r["root_pane"] as? [String: Any])?["pane_id"] as? String else { return false }
        return cli(["pane", "run", pane, command], socket: socket, bin: bin) != nil
    }

    /// Each agent herdr sees on that server, by pane: its state ("idle", "working", "blocked", "done", "unknown") and,
    /// when herdr's own integration reports it, the agent's session id.
    static func agents(socket: String, bin: String?) -> [String: (status: String, session: String?)] {
        guard let r = cli(["agent", "list"], socket: socket, bin: bin)?["result"] as? [String: Any], let list = r["agents"] as? [[String: Any]] else { return [:] }
        var out: [String: (String, String?)] = [:]
        for a in list {
            guard let pane = a["pane_id"] as? String else { continue }
            let s = a["agent_session"] as? [String: Any]
            out[pane] = (a["agent_status"] as? String ?? "unknown", s?["kind"] as? String == "id" ? s?["value"] as? String : nil)
        }
        return out
    }
}

/// cmux, a terminal app with workspaces and split surfaces. Its command line tool only answers processes inside cmux
/// (its default socket mode), so Perch drives it through AppleScript, where each terminal's id is the CMUX_SURFACE_ID its
/// processes carry and each workspace's id their CMUX_WORKSPACE_ID.
enum Cmux {
    static var app: NSRunningApplication? {
        ["com.cmuxterm.app", "com.cmuxterm.app.nightly"].lazy.compactMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }.first
    }
    static func activate() { app?.activate() }
    private static var name: String { app?.bundleIdentifier == "com.cmuxterm.app.nightly" ? "cmux NIGHTLY" : "cmux" }

    /// Shows that surface in its workspace and brings cmux forward. False when cmux is not running or the surface is gone.
    static func focus(workspace: String, surface: String) -> Bool {
        guard app != nil else { return false }
        return Terminals.run("""
            tell application "\(name)"
              set hits to (every terminal whose id is \(Terminals.appleQuote(surface)))
              if (count of hits) is 0 then return "no"
              focus item 1 of hits
              activate
              return "ok"
            end tell
            """) == "ok"
    }

    /// Types a line into that surface and presses Return. The text goes in as a paste, so Return is its own key.
    static func type(_ line: String, workspace: String, surface: String) -> Bool {
        guard app != nil else { return false }
        return Terminals.run("""
            tell application "\(name)"
              set hits to (every terminal whose id is \(Terminals.appleQuote(surface)))
              if (count of hits) is 0 then return "no"
              input text \(Terminals.appleQuote(line)) to item 1 of hits
              delay 0.1
              perform action "text:\\\\r" on item 1 of hits
              return "ok"
            end tell
            """) == "ok"
    }

    /// A new workspace that runs `command` in `cwd`, in front.
    static func open(_ command: String, in cwd: String) {
        guard app != nil || NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.cmuxterm.app") != nil else { return }
        Terminals.run("""
            tell application "\(app == nil ? "cmux" : name)"
              activate
              set t to new tab
              select tab t
              delay 0.8
              set term to focused terminal of t
              input text \(Terminals.appleQuote("cd \(Terminals.shellQuote(cwd)) && \(command)")) to term
              delay 0.1
              perform action "text:\\\\r" on term
            end tell
            """)
    }

    /// The surface cmux keeps for a session when its own hooks are on, even after it hibernated the agent
    /// (~/.cmuxterm/<agent>-hook-sessions.json). Visiting it resumes the session.
    static func heldSurface(agent: String, session: String) -> (workspace: String, surface: String)? {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cmuxterm/\(agent)-hook-sessions.json")
        guard let data = try? Data(contentsOf: url), let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let s = (o["sessions"] as? [String: Any])?[session] as? [String: Any],
              let w = s["workspaceId"] as? String, let surface = s["surfaceId"] as? String else { return nil }
        return (w, surface)
    }
}

/// Coding agents running right now in a terminal, a herdr pane or a cmux surface, found from the process table and
/// their own environment. No permission needed.
enum LiveSessions {
    struct Hit: Equatable {
        let pid: pid_t, cwd: String, tty: String
        /// An Agent id.
        let agent: String
        /// The terminal app it shows in (a bundle id). For herdr, the terminal that shows a client of its server.
        let app: String?
        let place: Place
        let argv: [String]
        let started: Date
        /// herdr: the client attached to its server, which is where you see it. Nil when none is attached.
        let viewer: Viewer?
        /// herdr: the CLI the pane names (HERDR_BIN_PATH).
        let herdrBin: String?
    }
    /// A herdr client in a terminal: what shows a herdr server's panes.
    struct Viewer: Equatable { let pid: pid_t; let tty: String; let cwd: String; let app: String?; let place: Place; let session: String }

    /// Agent processes that have a terminal. The ones the Claude app, Codex app or OpenCode app start have none, so they are left out.
    static func all() -> [Hit] { scan().hits }

    /// The agents, and the herdr clients attached right now.
    static func scan() -> (hits: [Hit], viewers: [Viewer]) {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        var pids = [pid_t](repeating: 0, count: capacity)
        let n = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.size)))
        var found: [(pid: pid_t, agent: Agent, args: ProcessArgs, tty: String, cwd: String, ppid: pid_t, started: Date)] = []
        var viewers: [Viewer] = []
        var path = [CChar](repeating: 0, count: 4096)
        let interesting: Set<String> = ["claude", "codex", "opencode", "pi", "node", "bun", "herdr"]
        for pid in pids.prefix(max(0, n)) where pid > 0 {
            guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { continue }
            let exe = String(cString: path), name = (exe as NSString).lastPathComponent
            guard interesting.contains(name) || name.hasPrefix("codex-") || exe.contains("/claude/versions/") else { continue }
            var bsd = proc_bsdinfo()
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, Int32(MemoryLayout<proc_bsdinfo>.size)) > 0,
                  bsd.e_tdev != UInt32.max, let dev = devname(dev_t(bitPattern: bsd.e_tdev), S_IFCHR) else { continue }
            let tty = "/dev/" + String(cString: dev), cwd = workingDirectory(pid) ?? ""
            let args = arguments(pid) ?? ProcessArgs(executable: exe, argv: [], environment: [:])
            if name == "herdr" {
                // A client: `herdr`, `herdr --session x`, `herdr session attach x`. The server runs without a terminal.
                guard !args.argv.contains("server"), !args.argv.contains("--remote") else { continue }
                let session = value(after: "--session", in: args.argv) ?? (args.argv.count >= 4 && args.argv[1] == "session" && args.argv[2] == "attach" ? args.argv[3] : "default")
                viewers.append(Viewer(pid: pid, tty: tty, cwd: cwd, app: terminalApp(above: pid_t(bsd.pbi_ppid)), place: Place.from(environment: args.environment), session: session))
                continue
            }
            guard let agent = Agent.recognise(executable: exe, argv0: args.argv.first) else { continue }
            found.append((pid, agent, args, tty, cwd, pid_t(bsd.pbi_ppid), Date(timeIntervalSince1970: Double(bsd.pbi_start_tvsec))))
        }
        let hits = found.map { f in
            let place = Place.from(environment: f.args.environment)
            var viewer: Viewer?, app: String?
            if case .herdr(_, _, let session) = place {
                viewer = viewers.first { $0.session == session }
                app = viewer?.app
            } else {
                app = terminalApp(above: f.ppid)
            }
            return Hit(pid: f.pid, cwd: f.cwd, tty: f.tty, agent: f.agent.id, app: app, place: place, argv: f.args.argv, started: f.started,
                       viewer: viewer, herdrBin: f.args.environment["HERDR_BIN_PATH"])
        }
        return (hits, viewers)
    }

    private static func value(after flag: String, in argv: [String]) -> String? {
        guard let i = argv.firstIndex(of: flag), argv.indices.contains(i + 1) else { return nil }
        return argv[i + 1]
    }

    private static func workingDirectory(_ pid: pid_t) -> String? {
        var vnode = proc_vnodepathinfo()
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vnode, Int32(MemoryLayout<proc_vnodepathinfo>.size)) > 0 else { return nil }
        return withUnsafeBytes(of: vnode.pvi_cdir.vip_path) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
    }

    /// argv and the environment the process started with (KERN_PROCARGS2). Only your own processes.
    static func arguments(_ pid: pid_t) -> ProcessArgs? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0 else { return nil }
        return ProcessArgs.parse(Data(buf.prefix(size)))
    }

    /// The first app up the parent chain: the terminal (or editor) the session's shell lives in.
    static func terminalApp(above start: pid_t) -> String? {
        var pid = start
        for _ in 0..<12 where pid > 1 {
            if let app = NSRunningApplication(processIdentifier: pid), let id = app.bundleIdentifier, app.activationPolicy == .regular { return id }
            guard let up = parent(of: pid) else { return nil }
            pid = up
        }
        return nil
    }

    /// A process's parent, from the process table. Unlike proc_pidinfo it also works for processes owned by root,
    /// like the `login` that Terminal puts between itself and your shell.
    static func parent(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc(), size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }
}
