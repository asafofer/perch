import AppKit
import ApplicationServices
import Darwin
import PerchCore

/// Terminal apps. Pick up goes back to the tab a session runs in, or opens it again in the terminal you use.
enum Terminals {
    static let terminal = "com.apple.Terminal", warp = "dev.warp.Warp-Stable", iterm = "com.googlecode.iterm2", ghostty = "com.mitchellh.ghostty", cmux = "com.cmuxterm.app", agterm = Agterm.bundle
    /// Every app that counts as a terminal, with the name its icon goes by in the page.
    static let keys: [String: String] = [
        terminal: "terminal", iterm: "iterm", ghostty: "ghostty", cmux: "cmux", "com.cmuxterm.app.nightly": "cmux", agterm: "agterm", warp: "warp",
        "com.github.wez.wezterm": "wezterm", "net.kovidgoyal.kitty": "kitty", "com.microsoft.VSCode": "vscode",
        "com.todesktop.230313mzl4w4u92": "cursor", "dev.zed.Zed": "zed",
    ]
    /// The ones Perch can open a new session in.
    static let opens: Set<String> = [terminal, iterm, ghostty, cmux, agterm]

    /// The terminal you used last, if Perch can open a session in it; Terminal otherwise.
    static var preferred: String { Prefs.lastTerminal.flatMap { opens.contains($0) ? $0 : nil } ?? terminal }

    /// Opens a new window (a workspace in cmux, a session in agterm) in `cwd` that runs `command`, and says which app it
    /// opened in: Terminal when agterm could not make the session.
    @discardableResult
    static func open(_ command: String, in cwd: String, app: String = preferred) -> String {
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
        case agterm:
            if !Agterm.open(command, in: cwd) { return open(command, in: cwd, app: terminal) }
        default:
            run("tell application \"Terminal\"\nactivate\ndo script \(appleQuote(typed))\nend tell")
        }
        return app
    }

    /// Where a session was brought forward: the app in front, and whether what it shows now is that session's own tab.
    /// Not `exact` when Perch could only bring the app forward or pick between tabs that look alike: a reply is never
    /// pasted there, since it would land in whichever tab was in front.
    struct Shown { let app: String; let exact: Bool }

    /// Brings what this session runs in to the front and says which app has it: its herdr pane (in the terminal that shows
    /// herdr), its tmux pane (in the terminal of the tmux client that shows it), its cmux surface, or its terminal tab
    /// (Terminal and iTerm2 by tty, Ghostty by folder; any other terminal is brought forward as a whole). Nil when there is
    /// nothing to bring forward.
    @discardableResult
    static func focus(_ live: LiveSessions.Hit, hints: [String] = []) -> Shown? {
        switch live.place {
        case .herdr(let pane, let socket, let session):
            Herdr.focus(pane: pane, socket: socket, bin: live.bin)
            if let v = live.viewer { return show(v) }
            // Nothing shows that server: open herdr in your terminal, on the pane just focused.
            open(Herdr.attach(session: session, bin: live.bin), in: live.cwd)
            return Shown(app: preferred, exact: true)
        case .tmux(let pane, let socket):
            // The client already on that session (else the one used last) moves to the pane, and its terminal comes forward.
            if let v = live.viewer, Tmux.show(pane: pane, socket: socket, client: v.tty, bin: live.bin) { return show(v) }
            // No client attached: open one in your terminal, on that pane.
            open(Tmux.attach(pane: pane, socket: socket, bin: live.bin), in: live.cwd)
            return Shown(app: preferred, exact: true)
        case .cmux(let workspace, let surface):
            if Cmux.focus(workspace: workspace, surface: surface) { return Shown(app: cmux, exact: true) }
            return focusTab(app: live.app, tty: live.tty, cwd: live.cwd, hints: hints)
        case .agterm(let window, let session, let pane):
            if Agterm.focus(window: window, session: session, pane: pane) { return Shown(app: agterm, exact: true) }
            return focusTab(app: live.app, tty: live.tty, cwd: live.cwd, hints: hints)
        case .tab:
            if live.app == warp, let url = live.warpFocus, focusWarp(url) { return Shown(app: warp, exact: true) }
            return focusTab(app: live.app, tty: live.tty, cwd: live.cwd, hints: hints)
        }
    }

    /// Opens a session's own Warp link, which lands on its tab exactly. True once Warp is in front and has had time to switch
    /// tabs: Warp in front already says nothing about which tab is, and it switches in about 0.2 s.
    private static func focusWarp(_ url: URL) -> Bool {
        let wasFront = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == warp
        guard NSWorkspace.shared.open(url) else { return false }
        if wasFront { Thread.sleep(forTimeInterval: 0.35); return true }
        for _ in 0..<30 {
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == warp { Thread.sleep(forTimeInterval: 0.1); return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
    }

    /// The terminal showing a herdr client, brought forward at that client's tab.
    static func show(_ v: LiveSessions.Viewer) -> Shown? {
        if case .cmux(let w, let s) = v.place, Cmux.focus(workspace: w, surface: s) { return Shown(app: cmux, exact: true) }
        if case .agterm(let w, let s, let pane) = v.place, Agterm.focus(window: w, session: s, pane: pane) { return Shown(app: agterm, exact: true) }
        return focusTab(app: v.app, tty: v.tty, cwd: v.cwd)
    }

    /// Warp has no way to ask for a tab, so Perch switches tabs with their own keys (Command+1 to 9) and reads each one through
    /// Accessibility: the window's title and the terminal text on screen. It stops on the tab that shows the session, and
    /// puts you back where you were when none does. Nil when no tab was picked; else whether it is surely the session's
    /// (`WarpTabs.sure`). With several windows, only words that session alone has make it sure: the windows after the
    /// one picked are never read. Blocks for a second or two.
    private static func switchWarpTab(cwd: String, hints: [String]) -> Bool? {
        guard AXIsProcessTrusted(), let running = NSRunningApplication.runningApplications(withBundleIdentifier: warp).first else { return nil }
        running.activate()
        Thread.sleep(forTimeInterval: 0.3)
        let ax = AXUIElementCreateApplication(running.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 1)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let trace = ProcessInfo.processInfo.environment["PERCH_TRACE"] != nil
        let windows = (ConductorApp.attr(ax, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        for window in windows {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            func read() -> WarpTabs.Reading {
                let text = ConductorApp.first(in: [window], limit: 60) { ConductorApp.attr($0, kAXRoleAttribute) as? String == "AXTextArea" }
                return WarpTabs.Reading(title: ConductorApp.attr(window, kAXTitleAttribute) as? String ?? "", text: text.flatMap { ConductorApp.attr($0, kAXValueAttribute) as? String } ?? "")
            }
            let start = read()
            var seen: [WarpTabs.Reading] = [], hit: Int?
            for n in 1...9 {
                press(digit: n, with: .maskCommand)
                Thread.sleep(forTimeInterval: 0.15)
                let r = read()
                seen.append(r)
                let score = WarpTabs.score(r, cwd: cwd, home: home, hints: hints)
                if trace { NSLog("Perch: Warp tab \(n): \(r.title.prefix(40)) score \(score)") }
                if score >= WarpTabs.certain { hit = n - 1; break }
            }
            if hit == nil { hit = WarpTabs.best(seen, cwd: cwd, home: home, hints: hints) }
            if let hit {
                // Pressing digits past the last tab does nothing, so a tab found early may not be where the keys ended.
                if seen.count != hit + 1 { press(digit: hit + 1, with: .maskCommand) }
                if windows.count > 1 { return WarpTabs.score(seen[hit], cwd: cwd, home: home, hints: hints) >= WarpTabs.certain }
                return WarpTabs.sure(seen, hit, cwd: cwd, home: home, hints: hints)
            }
            // Nothing here: back to the tab this window was on.
            if let back = seen.firstIndex(of: start) { press(digit: back + 1, with: .maskCommand) }
        }
        return nil
    }

    /// A key press with a modifier, sent to whatever is in front.
    private static func press(digit n: Int, with flags: CGEventFlags) {
        let codes = [18, 19, 20, 21, 23, 22, 26, 28, 25]   // 1 to 9 on a US layout
        let src = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(codes[n - 1]), keyDown: down)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
        }
    }

    /// A terminal by folder (Ghostty, cmux) is only surely the session's when no other terminal there is in that folder:
    /// with several, the first comes forward as a guess.
    static func focusTab(app: String?, tty: String, cwd: String, hints: [String] = []) -> Shown? {
        let folder = cwd
        let tty = appleQuote(tty), cwd = appleQuote(cwd)
        let byFolder = { (name: String) in """
            tell application "\(name)"
              set hits to (every terminal whose working directory is \(cwd))
              if (count of hits) is 0 then return "no"
              focus item 1 of hits
              activate
              if (count of hits) is 1 then return "ok"
              return "guess"
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
        if let script = scripts[app], let said = run(script), said == "ok" || said == "guess" { return Shown(app: app, exact: said == "ok") }
        if app == warp, let sure = switchWarpTab(cwd: folder, hints: hints) { return Shown(app: app, exact: sure) }
        // No way to pick the tab: bring its terminal forward, which is most of the way there.
        NSRunningApplication.runningApplications(withBundleIdentifier: app).first?.activate()
        return Shown(app: app, exact: false)
    }

    /// Types a line into what runs this session and presses Return, without bringing it forward, the clipboard or
    /// Accessibility: a herdr or tmux pane, cmux surface or agterm pane exactly, Terminal and iTerm2 by tty, Ghostty by folder when only
    /// one of its terminals is in that folder. False where it cannot.
    /// Return goes a moment after the words, as for tmux and Ghostty: Codex takes words that arrive at once as a paste, and
    /// a Return inside a paste is a new line, not Send. Terminal cannot type without its own Return, so Codex gets one more, alone.
    static func type(_ line: String, into live: LiveSessions.Hit) -> Bool {
        switch live.place {
        case .herdr(let pane, let socket, _): return Herdr.type(line, pane: pane, socket: socket, bin: live.bin)
        case .tmux(let pane, let socket): return Tmux.type(line, pane: pane, socket: socket, bin: live.bin)
        case .cmux(let w, let s): if Cmux.type(line, workspace: w, surface: s) { return true }
        case .agterm(let w, let s, let pane): if Agterm.type(line, window: w, session: s, pane: pane) { return true }
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
                    do script \(text) in t\(live.agent == Agent.codex.id ? "\n                    delay 0.3\n                    do script \"\" in t" : "")
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
                      tell s to write text \(text) newline no
                      delay 0.1
                      tell s to write text \"\"
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
              if (count of hits) is not 1 then return "no"
              input text \(appleQuote(line)) to item 1 of hits
              delay 0.1
              perform action "text:\\\\r" on item 1 of hits
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
    static func run(_ source: String, quiet: Bool = false) -> String? {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript"); p.arguments = ["-e", source]
        let out = Pipe(), err = Pipe(); p.standardOutput = out; p.standardError = err
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            if !quiet { NSLog("Perch: AppleScript failed: \(String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")") }
            return nil
        }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Runs a command line tool and returns what it printed, or nil when it failed.
    @discardableResult
    static func tool(_ path: String, _ args: [String], env: [String: String] = [:]) -> String? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
        if !env.isEmpty { p.environment = ProcessInfo.processInfo.environment.merging(env) { _, new in new } }
        // Nothing reads what it says on stderr, so that goes nowhere: an unread pipe that fills up blocks the tool for good.
        let out = Pipe(); p.standardOutput = out; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        if ProcessInfo.processInfo.environment["PERCH_TRACE"] != nil { NSLog("%@", "Perch: \((path as NSString).lastPathComponent) \(args.joined(separator: " ")) -> \(p.terminationStatus)") }
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
    /// Runs a command on that server. Some print JSON and some print nothing, so success is the exit status.
    @discardableResult
    private static func act(_ args: [String], socket: String, bin hint: String?) -> Bool {
        Terminals.tool(bin(hint), args, env: ["HERDR_SOCKET_PATH": socket]) != nil
    }
    /// Runs a command that answers in JSON, and reads the answer.
    private static func cli(_ args: [String], socket: String, bin hint: String?) -> [String: Any]? {
        guard let out = Terminals.tool(bin(hint), args, env: ["HERDR_SOCKET_PATH": socket]) else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [String: Any]
    }

    /// Shows the pane in every client attached to that server.
    @discardableResult
    static func focus(pane: String, socket: String, bin: String?) -> Bool {
        if act(["agent", "focus", pane], socket: socket, bin: bin) { return true }
        // Not an agent herdr recognises: show its tab.
        guard let r = cli(["pane", "get", pane], socket: socket, bin: bin)?["result"] as? [String: Any],
              let tab = (r["pane"] as? [String: Any])?["tab_id"] as? String else { return false }
        return act(["tab", "focus", tab], socket: socket, bin: bin)
    }

    /// The pane that has focus on that server, or nil when it cannot be read. With several clients attached it is only one
    /// of the places someone may be looking.
    static func focusedPane(socket: String, bin: String?) -> String? {
        ((cli(["api", "snapshot"], socket: socket, bin: bin)?["result"] as? [String: Any])?["snapshot"] as? [String: Any])?["focused_pane_id"] as? String
    }

    /// Types a line into the pane and presses Return: as a prompt to the agent there, else as raw text.
    static func type(_ line: String, pane: String, socket: String, bin: String?) -> Bool {
        if act(["agent", "prompt", pane, line], socket: socket, bin: bin) { return true }
        guard act(["pane", "send-text", pane, line], socket: socket, bin: bin) else { return false }
        return act(["pane", "send-keys", pane, "enter"], socket: socket, bin: bin)
    }

    /// The command that attaches to a server in a terminal.
    static func attach(session: String, bin: String?) -> String {
        let b = Terminals.shellQuote(Self.bin(bin))
        return session == "default" ? b : "\(b) --session \(Terminals.shellQuote(session))"
    }

    /// Whether a server answers on that socket.
    static func running(socket: String, bin: String?) -> Bool {
        FileManager.default.fileExists(atPath: socket) && act(["workspace", "list"], socket: socket, bin: bin)
    }

    /// A new tab in that workspace (or a new workspace if it is gone) that runs `command` in `cwd`, focused.
    @discardableResult
    static func run(_ command: String, cwd: String, workspace: String?, socket: String, bin: String?) -> Bool {
        var made = workspace.flatMap { cli(["tab", "create", "--workspace", $0, "--cwd", cwd, "--focus"], socket: socket, bin: bin) }
        if made == nil { made = cli(["workspace", "create", "--cwd", cwd, "--focus"], socket: socket, bin: bin) }
        guard let r = made?["result"] as? [String: Any], let pane = (r["root_pane"] as? [String: Any])?["pane_id"] as? String else { return false }
        return act(["pane", "run", pane, command], socket: socket, bin: bin)
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

/// tmux, whose server outlives the terminal like herdr's: each terminal showing it runs a client, which the CLI can move
/// to any pane. A pane's id (`%3`) holds while it lives; `-S` reaches the server an agent's TMUX names.
enum Tmux {
    /// The CLI: the server's own executable (its pid is in TMUX), else the usual places.
    static func bin(server: Int32?) -> String {
        var path = [CChar](repeating: 0, count: 4096)
        if let pid = server, proc_pidpath(pid, &path, UInt32(path.count)) > 0 {
            let exe = String(cString: path)
            if (exe as NSString).lastPathComponent.hasPrefix("tmux") { return exe }
        }
        return bin(nil)
    }
    /// The one a place remembered, while it is still there, else the usual places.
    static func bin(_ hint: String?) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ([hint].compactMap { $0 } + ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/run/current-system/sw/bin/tmux", home + "/.nix-profile/bin/tmux", "/usr/bin/tmux"])
            .first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/opt/homebrew/bin/tmux"
    }
    @discardableResult
    private static func cli(_ args: [String], socket: String, bin hint: String?) -> String? {
        Terminals.tool(bin(hint), ["-S", socket] + args)
    }

    /// Its panes and the clients attached to it, or nil when the server does not answer.
    static func ask(socket: String, bin: String) -> TmuxServer? {
        cli(TmuxServer.listing, socket: socket, bin: bin).map(TmuxServer.parse)
    }

    /// Moves that client to the pane: its session, window and pane. Older tmux only switches the session, hence the rest.
    static func show(pane: String, socket: String, client: String, bin: String?) -> Bool {
        cli(["switch-client", "-c", client, "-t", pane, ";", "select-window", "-t", pane, ";", "select-pane", "-t", pane], socket: socket, bin: bin) != nil
    }

    /// The pane a client shows now.
    static func showing(client: String, socket: String, bin: String?) -> String? {
        cli(["display-message", "-p", "-c", client, "#{pane_id}"], socket: socket, bin: bin).flatMap {
            let pane = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return pane.hasPrefix("%") ? pane : nil
        }
    }

    /// Types a line into the pane and presses Return, a beat apart so the agent reads Return as sending it. A pane scrolled
    /// back (copy mode) would take the words as commands, so it leaves that first.
    static func type(_ line: String, pane: String, socket: String, bin: String?) -> Bool {
        guard cli(["if-shell", "-F", "-t", pane, "#{pane_in_mode}", "send-keys -X -t \(pane) cancel", ";", "send-keys", "-t", pane, "-l", "--", TmuxServer.literal(line)], socket: socket, bin: bin) != nil else { return false }
        Thread.sleep(forTimeInterval: 0.1)
        return cli(["send-keys", "-t", pane, "Enter"], socket: socket, bin: bin) != nil
    }

    /// The command that attaches a terminal to that server, on the pane.
    static func attach(pane: String, socket: String, bin: String?) -> String {
        "\(Terminals.shellQuote(Self.bin(bin))) -S \(Terminals.shellQuote(socket)) attach-session -t \(Terminals.shellQuote(pane))"
    }

    /// A new window in that session (or a new session if it is gone) that runs `command` in `cwd` from your shell, so the
    /// shell stays when the agent ends. Nil when the server is not running: that would start one.
    static func run(_ command: String, cwd: String, session: String?, socket: String, bin: String?) -> String? {
        guard FileManager.default.fileExists(atPath: socket), cli(["list-sessions"], socket: socket, bin: bin) != nil else { return nil }
        let made = { (args: [String]) in cli(args + ["-P", "-F", "#{pane_id}", "-c", cwd], socket: socket, bin: bin)?.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let pane = session.flatMap({ $0.isEmpty ? nil : made(["new-window", "-t", "=\($0):"]) }) ?? made(["new-session", "-d"]),
              pane.hasPrefix("%"), type(command, pane: pane, socket: socket, bin: bin) else { return nil }
        return pane
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

/// agterm, a terminal with windows, workspaces, sessions and split panes. Every process it runs carries its window, session
/// and pane ids (AGTERM_WINDOW_ID, AGTERM_SESSION_ID, AGTERM_PANE_ID), and its command line tool drives it over its control
/// socket from outside agterm too, so no AppleScript.
enum Agterm {
    static let bundle = "com.umputun.agterm"
    static var app: NSRunningApplication? { NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first }

    nonisolated(unsafe) private static var foundBin: String?

    /// The CLI agterm ships inside its app, else the one on the usual paths. Kept once found, so an install made later is still picked up.
    static var bin: String? {
        if let foundBin { return foundBin }
        let inside = AppIcons.url("agterm").map { $0.appendingPathComponent("Contents/MacOS/agtermctl").path }
        foundBin = ([inside].compactMap { $0 } + ["/opt/homebrew/bin/agtermctl", "/usr/local/bin/agtermctl"]).first { FileManager.default.isExecutableFile(atPath: $0) }
        return foundBin
    }

    /// Runs a command and reads its JSON answer. Nil when agterm refused it.
    /// `text` goes last, after `--`, so a line starting with a dash is not read as an option.
    @discardableResult
    private static func cli(_ bin: String, _ args: [String], window: String? = nil, text: String? = nil) -> [String: Any]? {
        let out = Terminals.tool(bin, args + (window.map { ["--window", $0] } ?? []) + ["--json"] + (text.map { ["--", $0] } ?? []))
        guard let o = out.flatMap({ (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any] }), o["ok"] as? Bool == true else { return nil }
        return o["result"] as? [String: Any] ?? [:]
    }

    /// Raises the session's window, selects the session, shows its split if it is hidden, gives its pane the focus when
    /// the session has a split, and brings agterm forward. False when agterm is not running, the session or its pane is gone, or the split pane would not take
    /// the focus: the other pane may have it, and a reply pasted there would go to the wrong place. The tree is read first, so a session that is gone
    /// leaves your view where it was.
    static func focus(window: String?, session: String, pane: String) -> Bool {
        guard app != nil, let bin, let (kind, hasSplit, shown) = surface(bin, of: pane, session: session, window: window) else { return false }
        if let window { cli(bin, ["window", "select", window]) }
        guard cli(bin, ["session", "select", "--target", session], window: window) != nil else { return false }
        if hasSplit {
            if !shown, cli(bin, ["session", "split", "visibility", "on", "--target", session], window: window) == nil { return false }
            if cli(bin, ["session", "focus", kind, "--target", session], window: window) == nil { return false }
        }
        app?.activate()
        return true
    }

    /// Which of its session's panes a pane is now ("left" or "right"), whether the session has a split pane (`hasSplit`),
    /// and whether it shows it now (`split`, false after Cmd+D hid it): a split's panes can swap places.
    private static func surface(_ bin: String, of pane: String, session: String, window: String?) -> (kind: String, hasSplit: Bool, shown: Bool)? {
        guard let s = workspaces(bin, window: window).flatMap({ $0["sessions"] as? [[String: Any]] ?? [] }).first(where: { $0["id"] as? String == session }),
              let kind = (s["surfaces"] as? [[String: Any]])?.first(where: { ($0["paneID"] as? String)?.lowercased() == pane.lowercased() })?["kind"] as? String
        else { return nil }
        return (kind, s["hasSplit"] as? Bool == true, s["split"] as? Bool == true)
    }

    /// Every workspace in that window (the frontmost when nil), from its tree.
    private static func workspaces(_ bin: String, window: String?) -> [[String: Any]] {
        (cli(bin, ["tree"], window: window)?["tree"] as? [String: Any])?["workspaces"] as? [[String: Any]] ?? []
    }

    /// The pane that has the keyboard in the frontmost window: its active session's focused pane. Nil when it cannot be read.
    static func focusedPane() -> String? {
        guard app != nil, let bin,
              let workspace = workspaces(bin, window: nil).first(where: { $0["active"] as? Bool == true }),
              let session = (workspace["sessions"] as? [[String: Any]])?.first(where: { $0["active"] as? Bool == true }) else { return nil }
        // splitFocused is there for a hidden split too, and then the focused pane is the one shown.
        let kind = session["splitFocused"] as? Bool == true ? "right" : "left"
        return (session["surfaces"] as? [[String: Any]])?.first { $0["kind"] as? String == kind }?["paneID"] as? String
    }

    /// Types a line into the session's pane and presses Return, a beat apart so the agent reads Return as sending it. It
    /// types as keys do, so a newline in the line would send it early. The session is named because agterm otherwise
    /// looks for the pane in the window's active session.
    static func type(_ line: String, window: String?, session: String, pane: String) -> Bool {
        guard app != nil, let bin else { return false }
        let args = ["session", "type", "--target", session, "--pane-id", pane]
        guard cli(bin, args, window: window, text: line) != nil else { return false }
        Thread.sleep(forTimeInterval: 0.1)
        return cli(bin, args, window: window, text: "\r") != nil
    }

    /// A new session in `cwd` that runs `command` from your shell, so the shell stays when the agent ends; selected, in
    /// front. agterm is opened first when it is not running. False when no session could be made.
    @discardableResult
    static func open(_ command: String, in cwd: String) -> Bool {
        guard let bin else { return false }
        // `session new` fails until agterm has restored a window, which takes a few seconds after it starts.
        var tries = 10
        if app == nil {
            guard let url = AppIcons.url("agterm") else { return false }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            tries = 30
        }
        var id: String?
        for i in 0..<tries {
            id = cli(bin, ["session", "new", "--cwd", cwd])?["id"] as? String
            if id != nil { break }
            if i < tries - 1 { Thread.sleep(forTimeInterval: 0.5) }
        }
        guard let id else { return false }
        guard cli(bin, ["session", "type", "--target", id], text: command + "\n") != nil else { return false }
        app?.activate()
        return true
    }
}

/// Coding agents running right now in a terminal, a herdr pane, a cmux surface or an agterm pane, found from the process table and
/// their own environment. No permission needed.
enum LiveSessions {
    struct Hit: Equatable {
        let pid: pid_t, cwd: String, tty: String
        /// An Agent id.
        let agent: String
        /// The terminal app it shows in (a bundle id). For herdr and tmux, the terminal that shows a client of its server.
        let app: String?
        let place: Place
        let argv: [String]
        let started: Date
        /// herdr and tmux: the client attached to its server, which is where you see it. Nil when none is attached.
        let viewer: Viewer?
        /// The multiplexer's CLI: the one a herdr pane names (HERDR_BIN_PATH), or the tmux server's own.
        let bin: String?
        /// tmux: the session its pane is in.
        var tmuxSession: String? = nil
        /// Warp: the link that brings its own tab forward (`WarpTabs.focusLink`).
        var warpFocus: URL? = nil
    }
    /// A herdr or tmux client in a terminal: what shows a herdr server's panes, or a tmux session. `tmux` is the socket of
    /// that tmux server and `bin` its CLI; nil for herdr, whose `session` names the server.
    struct Viewer: Equatable {
        let pid: pid_t; let tty: String; let cwd: String; let app: String?; let place: Place; let session: String
        var tmux: String? = nil, bin: String? = nil
    }

    /// Agent processes that have a terminal. The ones the Claude app, Codex app or OpenCode app start have none, so they are left out.
    static func all() -> [Hit] { scan().hits }

    /// The agents, and the herdr and tmux clients attached right now.
    static func scan() -> (hits: [Hit], viewers: [Viewer]) {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        var pids = [pid_t](repeating: 0, count: capacity)
        let n = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.size)))
        var found: [(pid: pid_t, agent: Agent, args: ProcessArgs, tty: String, cwd: String, ppid: pid_t, started: Date)] = []
        var viewers: [Viewer] = []
        var path = [CChar](repeating: 0, count: 4096)
        for pid in pids.prefix(max(0, n)) where pid > 0 {
            guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { continue }
            let exe = String(cString: path), name = (exe as NSString).lastPathComponent
            guard name == "herdr" || Agent.mayBe(exe) else { continue }
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
        // Each tmux server an agent runs in, asked once: its panes, and its clients as viewers.
        var tmux: [String: (bin: String, said: TmuxServer)] = [:]
        for f in found {
            guard case .tmux(_, let socket) = Place.from(environment: f.args.environment), tmux[socket] == nil else { continue }
            let bin = Tmux.bin(server: f.args.environment["TMUX"].flatMap(TmuxServer.socket)?.server)
            guard let said = Tmux.ask(socket: socket, bin: bin) else { continue }
            tmux[socket] = (bin, said)
            viewers += said.clients.map { viewer($0, socket: socket, bin: bin) }
        }
        let hits = found.map { f in
            var place = Place.from(environment: f.args.environment)
            var viewer: Viewer?, app: String?, bin = f.args.environment["HERDR_BIN_PATH"], tmuxSession: String?
            if case .tmux(let pane, let socket) = place {
                // Only a process on that pane's own terminal is in it: an app started from tmux (an editor) passes TMUX on
                // to the shells in its own terminal.
                if let server = tmux[socket], let p = server.said.panes[pane], p.tty == f.tty {
                    bin = server.bin; tmuxSession = p.sessions.first
                    let c = server.said.viewer(of: pane)
                    viewer = viewers.first { $0.tmux == socket && $0.pid == c?.pid }
                } else { place = .tab }
            }
            switch place {
            case .herdr(_, _, let session):
                viewer = viewers.first { $0.tmux == nil && $0.session == session }
                app = viewer?.app
            case .tmux: app = viewer?.app
            case .agterm:
                // With agterm's live sessions a pane's shell runs under a daemon of its own, not under agterm. An app other than
                // agterm above it (an editor started from agterm) passed agterm's variables on to its own terminal.
                app = terminalApp(above: f.ppid) ?? Terminals.agterm
                if app != Terminals.agterm { place = .tab }
            default: app = terminalApp(above: f.ppid)
            }
            return Hit(pid: f.pid, cwd: f.cwd, tty: f.tty, agent: f.agent.id, app: app, place: place, argv: f.args.argv, started: f.started,
                       viewer: viewer, bin: bin, tmuxSession: tmuxSession, warpFocus: WarpTabs.focusLink(f.args.environment))
        }
        return (hits, viewers)
    }

    /// A tmux client as a viewer: the terminal it runs in, and where in it (a cmux surface, say).
    static func viewer(_ c: TmuxServer.Client, socket: String, bin: String) -> Viewer {
        Viewer(pid: c.pid, tty: c.tty, cwd: workingDirectory(c.pid) ?? "", app: terminalApp(above: c.pid),
               place: Place.from(environment: arguments(c.pid)?.environment ?? [:]), session: c.session, tmux: socket, bin: bin)
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
