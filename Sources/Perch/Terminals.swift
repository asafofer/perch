import AppKit
import Darwin

/// Terminal apps Perch knows by bundle id. Pick up opens a session in the one you last used.
enum Terminals {
    static let terminal = "com.apple.Terminal", iterm = "com.googlecode.iterm2", ghostty = "com.mitchellh.ghostty"
    /// Every terminal that counts as "you are in a terminal". Only the first three can open a session for Perch.
    static let all: Set<String> = [terminal, iterm, ghostty, "dev.warp.Warp-Stable", "com.github.wez.wezterm", "net.kovidgoyal.kitty", "com.cmuxterm.app"]

    /// The terminal you used last, if Perch can open a session in it; Terminal otherwise.
    static var preferred: String { [terminal, iterm, ghostty].contains(Prefs.lastTerminal) ? Prefs.lastTerminal! : terminal }

    /// Opens a new window in `cwd` that runs `command`.
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
        default:
            run("tell application \"Terminal\"\nactivate\ndo script \(appleQuote(typed))\nend tell")
        }
    }

    /// Brings the exact tab running this terminal session to the front, and says which app has it.
    @discardableResult
    static func focus(_ live: LiveSessions.Hit) -> String? {
        let tty = appleQuote(live.tty)
        let scripts: [(String, String)] = [
            (terminal, """
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
            """),
            (iterm, """
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
            """),
            (ghostty, """
            tell application "Ghostty"
              set hits to (every terminal whose working directory is \(appleQuote(live.cwd)))
              if (count of hits) is 0 then return "no"
              focus item 1 of hits
              activate
              return "ok"
            end tell
            """),
        ]
        // Only ask apps that are running: asking one that is not would launch it.
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        for (app, script) in scripts where running.contains(app) {
            if run(script) == "ok" { return app }
        }
        return nil
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

/// Claude Code sessions running right now in a terminal, found from the process table. No permission needed.
enum LiveSessions {
    struct Hit: Equatable { let pid: pid_t; let cwd: String; let tty: String }

    /// Claude Code processes that have a terminal. Ones the Claude app starts have none, so they are left out.
    static func claude() -> [Hit] {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        var pids = [pid_t](repeating: 0, count: capacity)
        let n = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.size)))
        var out: [Hit] = []
        var path = [CChar](repeating: 0, count: 4096)
        for pid in pids.prefix(max(0, n)) where pid > 0 {
            guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { continue }
            let exe = String(cString: path)
            // The native installer runs ~/.local/share/claude/versions/<version>; other installs are named claude.
            guard exe.contains("/claude/versions/") || (exe as NSString).lastPathComponent == "claude" else { continue }
            var bsd = proc_bsdinfo()
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, Int32(MemoryLayout<proc_bsdinfo>.size)) > 0,
                  bsd.e_tdev != UInt32.max, let name = devname(dev_t(bitPattern: bsd.e_tdev), S_IFCHR) else { continue }
            var vnode = proc_vnodepathinfo()
            guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vnode, Int32(MemoryLayout<proc_vnodepathinfo>.size)) > 0 else { continue }
            let cwd = withUnsafeBytes(of: vnode.pvi_cdir.vip_path) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
            out.append(Hit(pid: pid, cwd: cwd, tty: "/dev/" + String(cString: name)))
        }
        return out
    }
}

/// Reply borrows the clipboard to paste. This puts back what you had, every type of it.
enum Clipboard {
    typealias Saved = [[NSPasteboard.PasteboardType: Data]]
    static func save() -> Saved {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in
            Dictionary(item.types.compactMap { t in item.data(forType: t).map { (t, $0) } }, uniquingKeysWith: { a, _ in a })
        }
    }
    static func restore(_ saved: Saved) {
        let pb = NSPasteboard.general
        pb.clearContents()
        guard !saved.isEmpty else { return }
        pb.writeObjects(saved.map { types in
            let item = NSPasteboardItem()
            for (t, data) in types { item.setData(data, forType: t) }
            return item
        })
    }
}
