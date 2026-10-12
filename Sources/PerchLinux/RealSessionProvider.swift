import CPerchLinux
import Foundation
import PerchCore

/// The home folder whose sessions Perch reads: $PERCH_HOME, a stand-in to try Perch on copied sessions (as HookInstaller
/// takes it), else yours.
enum SessionHome {
    static let url = ProcessInfo.processInfo.environment["PERCH_HOME"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser
    static var path: String { url.path }
}

/// Reads the recent sessions of Claude Code, Codex, OpenCode and pi and turns each into a card. One row per session.
/// Linux has no Claude app and no Codex app, so every session is a terminal one: it goes back to where it runs, or opens
/// again with its agent's resume command.
final class RealSessionProvider: SessionProviding, @unchecked Sendable {
    /// The list shows five rows at a time and scrolls for the rest.
    var maxProjects = 15
    /// Whether an agent (an Agent id) is switched on in Perch's settings.
    var isEnabled: (String) -> Bool = { Prefs.enabledSources.contains($0) }
    struct Count { let count: Int; let names: [String] }
    private var _counts: [String: Count] = [:]
    /// What the last scan found per agent, before any agent is switched off. Onboarding shows this.
    var counts: [String: Count] { lock.lock(); defer { lock.unlock() }; return _counts }
    /// What the last scan read, so nothing has to read the files again to write about them.
    private var _inputs: [String: (digest: SessionDigest, git: GitInfo?)] = [:]
    private let lock = NSLock()
    var inputs: [String: (digest: SessionDigest, git: GitInfo?)] { lock.lock(); defer { lock.unlock() }; return _inputs }
    private let scanner: SessionScanner

    /// The Claude app's list and Conductor's database are Mac folders: here they are simply absent, and every Claude Code
    /// transcript started from a terminal gets its row.
    init(home: URL = SessionHome.url) {
        scanner = SessionScanner(home: home, desktop: DesktopSessions(root: home.appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")))
    }

    func parkedProjects() -> [Project] {
        var all = scanner.claude(limit: maxProjects) + scanner.codex(limit: maxProjects) + scanner.opencode(limit: maxProjects) + scanner.pi(limit: maxProjects)
        all.sort { $0.last > $1.last }
        // No Codex app here: a thread from an editor's Codex extension resumes in a terminal like any other.
        for i in all.indices { all[i].project.terminal = true }
        var perApp: [String: (seen: Set<String>, names: [String])] = [:]
        for item in all {
            let key = item.project.app, cwd = item.project.cwd ?? item.project.id
            var entry = perApp[key] ?? ([], [])
            if entry.seen.insert(cwd).inserted { entry.names.append(item.project.name) }
            perApp[key] = entry
        }
        lock.lock(); _counts = perApp.mapValues { Count(count: $0.names.count, names: $0.names) }; lock.unlock()
        var out = Array(all.filter { isEnabled($0.project.app) }.prefix(maxProjects))
        if !out.isEmpty {
            var projects = out.map(\.project)
            Self.placeTerminalSessions(&projects)
            for i in out.indices { out[i].project = projects[i] }
        }
        let fresh = Dictionary(out.map { ($0.project.id, (digest: $0.digest, git: $0.git)) }, uniquingKeysWith: { a, _ in a })
        lock.lock(); _inputs = fresh; lock.unlock()
        return out.map(\.project)
    }

    /// For each terminal session: the process running it (if any), the terminal it shows in or would open in, whether that
    /// is inside herdr, and what herdr sees on screen. Where each one runs is remembered, so it can reopen there.
    static func placeTerminalSessions(_ projects: inout [Project]) {
        let (live, viewers) = LiveSessions.scan(), preferred = Terminals.preferred
        FocusProbe.setKnown((live, viewers))
        // herdr's own view of its panes, one query per server.
        var herdr: [String: [String: (status: String, session: String?)]] = [:]
        for h in live { if case .herdr(_, let socket, _) = h.place, herdr[socket] == nil { herdr[socket] = HerdrCLI.agents(socket: socket, bin: h.herdrBin) } }
        func seen(_ h: LiveSessions.Hit) -> (status: String, session: String?)? {
            if case .herdr(let pane, let socket, _) = h.place { return herdr[socket]?[pane] }
            return nil
        }
        // What the hooks said: the session each agent process last spoke for. A hook script's parent may be a shell
        // between it and the agent, so its pid is followed up to an agent process.
        var spoke: [pid_t: (session: String, at: Date)] = [:]
        let agentPids = Set(live.map(\.pid))
        for (session, s) in SessionPids.all() {
            var pid = s.pid
            for _ in 0..<4 where !agentPids.contains(pid) { guard let up = parentPid(of: pid), up > 1 else { break }; pid = up }
            guard agentPids.contains(pid), (spoke[pid]?.at ?? .distantPast) < s.at else { continue }
            spoke[pid] = (session, s.at)
        }
        let running = Running.match(live.map { Running.Process(agent: $0.agent, cwd: $0.cwd, argv: $0.argv, session: spoke[$0.pid]?.session ?? seen($0)?.session, started: $0.started) }, to: projects)
        var places = Prefs.places
        let before = places
        for i in projects.indices where projects[i].terminal {
            let id = projects[i].sessionId ?? projects[i].id
            if let h = running[i].map({ live[$0] }) {
                projects[i].pid = h.pid; projects[i].spot = Spot.key(h.place, tty: h.tty)
                switch h.place {
                case .herdr(_, let socket, let session):
                    projects[i].host = "herdr"; projects[i].via = h.app ?? preferred
                    places[id] = ["kind": "herdr", "socket": socket, "session": session, "workspace": h.place.herdrWorkspace ?? "", "bin": h.herdrBin ?? ""]
                    if let s = seen(h) { projects[i] = HerdrStatus.apply(s.status, to: projects[i]) }
                case .tab, .cmux:   // cmux is a Mac app: a cmux variable here is one inherited from a Mac, so it is a plain tab
                    projects[i].via = h.app ?? preferred
                    if let app = h.app { places[id] = ["kind": "tab", "app": app] }
                }
            } else {
                // Not running: where Pick up would open it again.
                let last = places[id]
                if last?["kind"] == "herdr" {
                    projects[i].host = "herdr"
                    projects[i].via = viewers.first { $0.session == last?["session"] }?.app ?? preferred
                } else {
                    projects[i].via = preferred
                }
            }
        }
        if places != before {
            if places.count > 300 { places = Dictionary(uniqueKeysWithValues: places.prefix(200).map { ($0.key, $0.value) }) }
            Prefs.places = places
        }
    }

    /// A process's parent, from /proc/<pid>/stat. The command name in brackets may hold spaces and brackets of its own, so
    /// the fields are read after the last one.
    static func parentPid(of pid: pid_t) -> pid_t? {
        guard let stat = try? String(contentsOfFile: "/proc/\(pid)/stat", encoding: .utf8), let close = stat.lastIndex(of: ")") else { return nil }
        let fields = stat[stat.index(after: close)...].split(separator: " ")
        return fields.count > 1 ? pid_t(fields[1]) : nil
    }
}

/// Where Pick up put you, so Reply knows whether typing would reach the right session.
enum Landing {
    case none
    /// The app now coming forward (an app id). `exact`: what has the keyboard there belongs to this session.
    case app(String, exact: Bool)
    /// A new terminal window that is starting the agent (`claude --resume`, `codex resume`) in `cwd`.
    case newTerminal(String, cwd: String, agent: String)
}

/// What Pick up does on Linux: a running terminal session goes back to where it runs (its herdr pane or its terminal's
/// window); a stopped one opens again where it last ran (Prefs.places), else in the terminal you used last, with its
/// agent's resume command.
@MainActor
enum Restorer {
    /// `done` runs on the main thread once the session is on its way.
    static func resume(_ p: Project, then done: @escaping @MainActor (Landing) -> Void = { _ in }) {
        guard p.terminal, let cwd = p.cwd, let id = p.sessionId else { done(.none); return }   // sample data does nothing
        let agent = p.app, pid = p.pid
        // Words only this session has on screen, for a terminal that cannot be asked which tab it is.
        let hints = [p.topic, p.asked.map { String($0.split(whereSeparator: \.isNewline).first ?? "").prefix(60) }.map(String.init)].compactMap { $0 }
        // herdr's tool and the process table are slow next to a frame, so this runs off the main thread, as on the Mac.
        DispatchQueue.global(qos: .userInitiated).async {
            let landing: Landing
            let live = LiveSessions.all()
            let hit = live.first { $0.pid == pid && $0.agent == agent } ?? live.first { $0.agent == agent && $0.argv.contains(id) }
            if ProcessInfo.processInfo.environment["PERCH_TRACE"] != nil { print("Perch pick up: \(agent) \(id.prefix(8)) in \(cwd); running: \(hit.map { "\($0.pid) \($0.place)" } ?? "no")") }
            if let hit, let app = Terminals.focus(hit, hints: hints) {
                landing = .app(app, exact: true)
            } else {
                landing = reopen(agent: agent, session: id, cwd: cwd, command: Agent.of(agent).resume(id))
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { done(landing) } }
        }
    }

    /// Opens a session that is not running again, where it last ran: a new tab in its herdr workspace (shown in the
    /// terminal attached to that server, or a new one that attaches), else a new window of your terminal.
    /// Blocks on the tools it drives, so call it off the main thread.
    nonisolated static func reopen(agent: String, session id: String, cwd: String, command: String) -> Landing {
        let last = Prefs.places[id], preferred = Terminals.preferred
        if last?["kind"] == "herdr", let socket = last?["socket"], let name = last?["session"] {
            let bin = last?["bin"].flatMap { $0.isEmpty ? nil : $0 }
            if HerdrCLI.running(socket: socket, bin: bin), HerdrCLI.run(command, cwd: cwd, workspace: last?["workspace"], socket: socket, bin: bin) {
                if let v = LiveSessions.scan().viewers.first(where: { $0.session == name }) { return .newTerminal(Terminals.show(v) ?? preferred, cwd: cwd, agent: agent) }
                Terminals.open(HerdrCLI.attach(session: name, bin: bin), in: cwd, app: preferred)
                return .newTerminal(preferred, cwd: cwd, agent: agent)
            }
        }
        Terminals.open(command, in: cwd, app: preferred)
        return .newTerminal(preferred, cwd: cwd, agent: agent)
    }
}

/// What the scan and Pick up need of herdr's command line: what it sees in each pane, whether a server answers, a new tab
/// that runs a command, and the command that attaches to a server. herdr prints nothing when some commands work, so
/// success is the exit status. (Mac: Herdr in Terminals.swift. Focusing and typing into a pane are Terminals' job.)
enum HerdrCLI {
    /// The CLI: the one the pane says it came with (HERDR_BIN_PATH), else the usual places.
    static func bin(_ hint: String?) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/herdr" }
        return ([hint].compactMap { $0 } + [home + "/.local/bin/herdr", home + "/.cargo/bin/herdr", "/usr/local/bin/herdr", "/usr/bin/herdr"] + path)
            .first { FileManager.default.isExecutableFile(atPath: $0) } ?? "herdr"
    }

    /// Runs the CLI against that server: its output when it exits 0, else nil.
    private static func tool(_ args: [String], socket: String, bin hint: String?) -> String? {
        let p = Process()
        let b = bin(hint)
        if b.hasPrefix("/") { p.executableURL = URL(fileURLWithPath: b); p.arguments = args }
        else { p.executableURL = URL(fileURLWithPath: "/usr/bin/env"); p.arguments = [b] + args }
        p.environment = ProcessInfo.processInfo.environment.merging(["HERDR_SOCKET_PATH": socket]) { _, new in new }
        let out = Pipe()
        p.standardOutput = out; p.standardError = FileHandle.nullDevice; p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }
    private static func act(_ args: [String], socket: String, bin: String?) -> Bool { tool(args, socket: socket, bin: bin) != nil }
    private static func cli(_ args: [String], socket: String, bin: String?) -> [String: Any]? {
        guard let out = tool(args, socket: socket, bin: bin) else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [String: Any]
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
    static func run(_ command: String, cwd: String, workspace: String?, socket: String, bin: String?) -> Bool {
        var made = workspace.flatMap { $0.isEmpty ? nil : cli(["tab", "create", "--workspace", $0, "--cwd", cwd, "--focus"], socket: socket, bin: bin) }
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
