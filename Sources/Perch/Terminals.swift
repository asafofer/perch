import AppKit
import Darwin

/// Terminal apps. Pick up goes back to the tab a session runs in, or opens it again in the terminal you use.
enum Terminals {
    static let terminal = "com.apple.Terminal", iterm = "com.googlecode.iterm2", ghostty = "com.mitchellh.ghostty", cmux = "com.cmuxterm.app"
    /// Every app that counts as a terminal, with the name its icon goes by in the page.
    static let keys: [String: String] = [
        terminal: "terminal", iterm: "iterm", ghostty: "ghostty", cmux: "cmux", "dev.warp.Warp-Stable": "warp",
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
            let cli = Process(); cli.executableURL = URL(fileURLWithPath: "/Applications/cmux.app/Contents/Resources/bin/cmux")
            cli.arguments = ["new-workspace", "--cwd", cwd, "--command", command, "--focus", "true"]
            try? cli.run(); cli.waitUntilExit()
            NSRunningApplication.runningApplications(withBundleIdentifier: cmux).first?.activate()
        default:
            run("tell application \"Terminal\"\nactivate\ndo script \(appleQuote(typed))\nend tell")
        }
    }

    /// Brings the tab running this session to the front and says which app has it. Terminal and iTerm2 find the exact tab
    /// by its tty, Ghostty and cmux by its folder; any other terminal is brought forward as a whole.
    @discardableResult
    static func focus(_ live: LiveSessions.Hit) -> String? {
        let tty = appleQuote(live.tty), cwd = appleQuote(live.cwd)
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
        guard let app = live.app else { return nil }
        if let script = scripts[app], run(script) == "ok" { return app }
        // No way to pick the tab: bring its terminal forward, which is most of the way there.
        NSRunningApplication.runningApplications(withBundleIdentifier: app).first?.activate()
        return app
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

    static func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static func appleQuote(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
}

/// Claude Code and Codex running right now in a terminal, found from the process table. No permission needed.
enum LiveSessions {
    struct Hit: Equatable {
        let pid: pid_t, cwd: String, tty: String
        /// "claude" or "codex".
        let agent: String
        /// The terminal app it runs in (a bundle id), found by walking up its parents.
        let app: String?
    }

    /// Agent processes that have a terminal. The ones the Claude app starts have none, so they are left out.
    static func all() -> [Hit] {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        var pids = [pid_t](repeating: 0, count: capacity)
        let n = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.size)))
        var out: [Hit] = []
        var path = [CChar](repeating: 0, count: 4096)
        for pid in pids.prefix(max(0, n)) where pid > 0 {
            guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { continue }
            let exe = String(cString: path), name = (exe as NSString).lastPathComponent
            // The native installer runs ~/.local/share/claude/versions/<version>; other installs are named claude or codex.
            let agent = exe.contains("/claude/versions/") || name == "claude" ? "claude" : (name == "codex" || name.hasPrefix("codex-") ? "codex" : nil)
            guard let agent else { continue }
            var bsd = proc_bsdinfo()
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, Int32(MemoryLayout<proc_bsdinfo>.size)) > 0,
                  bsd.e_tdev != UInt32.max, let dev = devname(dev_t(bitPattern: bsd.e_tdev), S_IFCHR) else { continue }
            var vnode = proc_vnodepathinfo()
            guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vnode, Int32(MemoryLayout<proc_vnodepathinfo>.size)) > 0 else { continue }
            let cwd = withUnsafeBytes(of: vnode.pvi_cdir.vip_path) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
            out.append(Hit(pid: pid, cwd: cwd, tty: "/dev/" + String(cString: dev), agent: agent, app: terminalApp(above: pid_t(bsd.pbi_ppid))))
        }
        return out
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
