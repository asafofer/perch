import Foundation

// What the Linux app reads about processes and terminals, as text in and values out, so it can be tested anywhere:
// /proc's files, tmux's lists, kitty's and wezterm's JSON, which terminal is the system's own, how to open a window in each.

/// A line of /proc/<pid>/stat, the fields Perch needs.
public struct ProcStat: Equatable, Sendable {
    public let pid: Int32
    /// The process's name as the kernel keeps it (15 characters at most). A process that renamed itself shows its new name.
    public let comm: String
    public let ppid: Int32, pgrp: Int32, session: Int32
    /// The controlling terminal as a device number; 0 for none.
    public let ttyNr: Int32
    /// The foreground process group of that terminal.
    public let tpgid: Int32
    /// Clock ticks after boot.
    public let startTicks: UInt64

    /// The name sits in parentheses and may hold spaces and parentheses itself, so the fields are counted from the last ")".
    public static func parse(_ line: String) -> ProcStat? {
        guard let open = line.firstIndex(of: "("), let close = line.lastIndex(of: ")"), open < close,
              let pid = Int32(line[..<open].trimmingCharacters(in: .whitespaces)) else { return nil }
        let f = line[line.index(after: close)...].split(separator: " ", omittingEmptySubsequences: true)
        // f[0] is the state, then ppid, pgrp, session, tty_nr, tpgid; starttime is field 22 of the line, f[19].
        guard f.count > 19, let ppid = Int32(f[1]), let pgrp = Int32(f[2]), let session = Int32(f[3]), let tty = Int32(f[4]),
              let tpgid = Int32(f[5]), let start = UInt64(f[19]) else { return nil }
        return ProcStat(pid: pid, comm: String(line[line.index(after: open)..<close]), ppid: ppid, pgrp: pgrp, session: session,
                        ttyNr: tty, tpgid: tpgid, startTicks: start)
    }

    /// Its terminal as a path, nil when it has none.
    public var tty: String? { Self.ttyPath(ttyNr) }
    /// The process is what its terminal is talking to now: keys typed there reach it, not a shell or a pager in front of it.
    public var foreground: Bool { ttyNr != 0 && tpgid > 0 && tpgid == pgrp }

    /// A device number as a path: /dev/pts/N for pseudo-terminals (majors 136 to 143), /dev/ttyN for the virtual consoles.
    public static func ttyPath(_ nr: Int32) -> String? {
        let n = UInt32(bitPattern: nr)
        guard n != 0 else { return nil }
        let major = (n >> 8) & 0xfff, minor = (n & 0xff) | ((n >> 12) & 0xfff00)
        if (136...143).contains(major) { return "/dev/pts/\((major - 136) * 256 + minor)" }
        if major == 4 { return minor < 64 ? "/dev/tty\(minor)" : "/dev/ttyS\(minor - 64)" }
        return nil
    }
}

extension ProcessArgs {
    /// /proc/<pid>/cmdline and /proc/<pid>/environ: each argument and each `KEY=value` ended by a zero byte. The
    /// environment is the one the process started with. A process that renamed itself may leave its arguments as one
    /// string with spaces, or empty strings where they were.
    public static func parse(cmdline: Data, environ: Data, executable: String) -> ProcessArgs {
        func parts(_ d: Data) -> [String] { d.split(separator: 0, omittingEmptySubsequences: false).map { String(decoding: $0, as: UTF8.self) } }
        var argv = parts(cmdline)
        if argv.last == "" { argv.removeLast() }
        var env: [String: String] = [:]
        for e in parts(environ) {
            guard let eq = e.firstIndex(of: "="), eq != e.startIndex else { continue }
            let key = String(e[..<eq])
            if env[key] == nil { env[key] = String(e[e.index(after: eq)...]) }
        }
        return ProcessArgs(executable: executable, argv: argv, environment: env)
    }

    /// The executable as /proc/<pid>/exe reads, without the mark the kernel adds once the file is gone (the native Claude
    /// installer deletes the version a running session started from).
    public static func liveExecutable(_ link: String) -> String {
        link.hasSuffix(" (deleted)") ? String(link.dropLast(10)) : link
    }
}

/// tmux's own lists, read with formats Perch chooses.
public enum TmuxList {
    /// $TMUX in a pane: "socket,server pid,session index".
    public static func socket(fromEnv v: String?) -> String? {
        guard let v, let s = v.split(separator: ",", omittingEmptySubsequences: false).first, s.hasPrefix("/") else { return nil }
        return String(s)
    }

    /// A terminal attached to a tmux server, and the pane it shows (its session's current window's active pane).
    public struct Client: Equatable, Sendable {
        public let pid: Int32, tty: String, session: String, activity: Int, pane: String, paneTty: String
        public init(pid: Int32, tty: String, session: String, activity: Int, pane: String, paneTty: String) {
            self.pid = pid; self.tty = tty; self.session = session; self.activity = activity; self.pane = pane; self.paneTty = paneTty
        }
    }
    public static let clientFormat = "#{client_pid}\t#{client_tty}\t#{client_session}\t#{client_activity}\t#{pane_id}\t#{pane_tty}"
    public static func clients(_ out: String) -> [Client] {
        out.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 6, let pid = Int32(f[0]) else { return nil }
            return Client(pid: pid, tty: f[1], session: f[2], activity: Int(f[3]) ?? 0, pane: f[4], paneTty: f[5])
        }
    }

    /// A pane on a tmux server.
    public struct Pane: Equatable, Sendable {
        public let id: String, session: String, tty: String
        /// Copy mode or another mode: keys go to tmux, not to the program in the pane.
        public let inMode: Bool
        public init(id: String, session: String, tty: String, inMode: Bool) { self.id = id; self.session = session; self.tty = tty; self.inMode = inMode }
    }
    public static let paneFormat = "#{pane_id}\t#{session_name}\t#{pane_tty}\t#{pane_in_mode}"
    public static func panes(_ out: String) -> [Pane] {
        out.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 4, f[0].hasPrefix("%") else { return nil }
            return Pane(id: f[0], session: f[1], tty: f[2], inMode: f[3] != "0" && !f[3].isEmpty)
        }
    }

    /// The client to show a session's pane in: one attached to that session, the one used last; else any client of that
    /// server, which can switch to it. Nil when no terminal is attached.
    public static func client(for session: String, in clients: [Client]) -> Client? {
        clients.filter { $0.session == session }.max { $0.activity < $1.activity } ?? clients.max { $0.activity < $1.activity }
    }
}

/// `kitty @ ls`: OS windows, their tabs, and the windows (panes) in each.
public enum KittyList {
    /// The X window that holds a kitty window (KITTY_WINDOW_ID), so the right one comes forward.
    public static func platformWindow(of window: Int, in json: Data) -> UInt? {
        for os in osWindows(json) {
            let ids = ((os["tabs"] as? [[String: Any]]) ?? []).flatMap { ($0["windows"] as? [[String: Any]]) ?? [] }.compactMap { $0["id"] as? Int }
            if ids.contains(window) { return (os["platform_window_id"] as? NSNumber)?.uintValue }
        }
        return nil
    }

    /// The process in the window kitty has in front in that X window (the active tab's focused window), which is where
    /// its terminal is read. With no X window given, kitty's focused OS window.
    public static func frontPid(platformWindow: UInt?, in json: Data) -> Int32? {
        let all = osWindows(json)
        guard let os = all.first(where: { w in platformWindow.map { (w["platform_window_id"] as? NSNumber)?.uintValue == $0 } ?? (w["is_focused"] as? Bool == true) }) else { return nil }
        let tabs = (os["tabs"] as? [[String: Any]]) ?? []
        guard let tab = tabs.first(where: { $0["is_focused"] as? Bool == true }) ?? (tabs.count == 1 ? tabs.first : nil) else { return nil }
        let windows = (tab["windows"] as? [[String: Any]]) ?? []
        guard let w = windows.first(where: { $0["is_focused"] as? Bool == true }) ?? (windows.count == 1 ? windows.first : nil) else { return nil }
        return (w["pid"] as? NSNumber)?.int32Value
    }

    private static func osWindows(_ json: Data) -> [[String: Any]] { ((try? JSONSerialization.jsonObject(with: json)) as? [[String: Any]]) ?? [] }
}

/// `wezterm cli list --format json` and `wezterm cli list-clients --format json`.
public enum WeztermList {
    public struct Pane: Equatable, Sendable { public let id: Int, title: String, tty: String? }
    public static func panes(_ json: Data) -> [Pane] {
        (((try? JSONSerialization.jsonObject(with: json)) as? [[String: Any]]) ?? []).compactMap { p in
            guard let id = (p["pane_id"] as? NSNumber)?.intValue else { return nil }
            return Pane(id: id, title: p["title"] as? String ?? "", tty: p["tty_name"] as? String)
        }
    }
    /// The pane the GUI has focused, from its clients (the one used last when there are several).
    public static func focusedPane(_ json: Data) -> Int? {
        let clients = ((try? JSONSerialization.jsonObject(with: json)) as? [[String: Any]]) ?? []
        let idle = { (c: [String: Any]) in ((c["idle_time"] as? [String: Any])?["secs"] as? NSNumber)?.doubleValue ?? .infinity }
        return clients.filter { $0["focused_pane_id"] != nil }.min { idle($0) < idle($1) }.flatMap { ($0["focused_pane_id"] as? NSNumber)?.intValue }
    }
}

/// The system's own terminal, and how to open a window in each one Perch knows. Apps go by their windows' WM_CLASS, lowercased.
public enum TerminalLaunch {
    /// Each terminal's program, by app id.
    public static let binaries: [String: String] = [
        "xfce4-terminal": "xfce4-terminal", "gnome-terminal-server": "gnome-terminal", "kitty": "kitty", "alacritty": "alacritty",
        "org.wezfurlong.wezterm": "wezterm", "com.mitchellh.ghostty": "ghostty", "ghostty": "ghostty", "konsole": "konsole",
        "xterm": "xterm", "tilix": "tilix", "terminator": "terminator",
    ]

    /// A terminal named the way XFCE's helpers.rc or Debian's x-terminal-emulator name it, as an app id.
    public static func app(named raw: String) -> String? {
        var name = (raw as NSString).lastPathComponent.lowercased()
        if name.hasSuffix(".wrapper") { name = String(name.dropLast(8)) }
        if name.hasSuffix(".desktop") { name = String(name.dropLast(8)) }
        switch name {
        case "gnome-terminal", "org.gnome.terminal": return "gnome-terminal-server"
        case "wezterm", "org.wezfurlong.wezterm": return "org.wezfurlong.wezterm"
        case "ghostty", "com.mitchellh.ghostty": return "com.mitchellh.ghostty"
        case "xterm", "uxterm", "lxterm", "koi8rxterm": return "xterm"
        case "org.kde.konsole": return "konsole"
        default: return binaries[name] != nil ? name : nil
        }
    }

    /// XFCE's choice: `TerminalEmulator=xfce4-terminal` in ~/.config/xfce4/helpers.rc.
    public static func fromHelpersRC(_ text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            let l = line.trimmingCharacters(in: .whitespaces)
            guard l.hasPrefix("TerminalEmulator=") else { continue }
            return app(named: String(l.dropFirst("TerminalEmulator=".count)))
        }
        return nil
    }

    /// The command line that opens a new window of `app` in `cwd` running `command` in your shell, which stays open after
    /// it as a login shell there. Nil for apps Perch cannot open a window in (editors).
    public static func argv(app: String, cwd: String, command: String, shell: String) -> [String]? {
        let script = "cd \(quote(cwd)) && \(command); exec \(quote(shell)) -l"
        // Interactive and login, so the PATH your shell's files set (~/.local/bin, nvm) finds the agent.
        let run = [shell, "-l", "-i", "-c", script]
        switch app {
        case "xfce4-terminal": return ["xfce4-terminal", "--window", "--working-directory=\(cwd)", "-x"] + run
        case "gnome-terminal-server": return ["gnome-terminal", "--window", "--working-directory=\(cwd)", "--"] + run
        case "kitty": return ["kitty", "--directory", cwd] + run
        case "alacritty": return ["alacritty", "--working-directory", cwd, "-e"] + run
        case "org.wezfurlong.wezterm": return ["wezterm", "start", "--cwd", cwd, "--"] + run
        case "com.mitchellh.ghostty", "ghostty": return ["ghostty", "--working-directory=\(cwd)", "-e"] + run
        case "konsole": return ["konsole", "--workdir", cwd, "-e"] + run
        case "xterm": return ["xterm", "-e"] + run   // no folder flag: it starts where it is started
        case "tilix": return ["tilix", "--working-directory=\(cwd)", "-e", run.map(quote).joined(separator: " ")]   // one string
        case "terminator": return ["terminator", "--working-directory=\(cwd)", "-x"] + run
        default: return nil
        }
    }

    public static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    /// Text for a terminal program that turned on bracketed paste (every agent's prompt does): it arrives as one paste, so
    /// a line break in it is not Return.
    public static func bracketed(_ s: String) -> String {
        "\u{1b}[200~" + s.replacingOccurrences(of: "\u{1b}[201~", with: "") + "\u{1b}[201~"
    }
}

/// Which of a terminal's windows shows a session, by title, for a terminal that keeps several windows in one process and
/// cannot be asked. Agents put the session's topic in the title; shells put the folder.
public enum WindowPick {
    /// The index of the best title, nil when none says anything about the session. Titles go bottom to top, so a tie goes
    /// to the window nearer the top.
    public static func best(_ titles: [String], cwd: String, home: String, hints: [String]) -> Int? {
        let folder = cwd == home ? "~" : cwd.hasPrefix(home + "/") ? "~" + cwd.dropFirst(home.count) : cwd
        let base = (cwd as NSString).lastPathComponent
        var best: (i: Int, score: Int)?
        for (i, t) in titles.enumerated() {
            let title = t.lowercased()
            var score = 0
            for h in hints where h.count >= 3 && title.contains(h.lowercased()) { score += 4 }
            if !cwd.isEmpty, title.contains(folder.lowercased()) || title.contains(cwd.lowercased()) { score += 2 }
            else if base.count >= 2, cwd != home, title.contains(base.lowercased()) { score += 1 }
            if score > 0, score >= (best?.score ?? 0) { best = (i, score) }
        }
        return best?.i
    }
}
