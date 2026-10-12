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
        for h in live { if case .herdr(_, let socket, _) = h.place, herdr[socket] == nil { herdr[socket] = Herdr.agents(socket: socket, bin: h.herdrBin) } }
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
            if Herdr.running(socket: socket, bin: bin), Herdr.run(command, cwd: cwd, workspace: last?["workspace"], socket: socket, bin: bin) {
                if let v = LiveSessions.scan().viewers.first(where: { $0.session == name }) { return .newTerminal(Terminals.show(v) ?? preferred, cwd: cwd, agent: agent) }
                Terminals.open(Herdr.attach(session: name, bin: bin), in: cwd, app: preferred)
                return .newTerminal(preferred, cwd: cwd, agent: agent)
            }
        }
        Terminals.open(command, in: cwd, app: preferred)
        return .newTerminal(preferred, cwd: cwd, agent: agent)
    }
}
