import AppKit
import PerchCore

/// Reads the recent sessions of Claude Code, Codex, OpenCode, pi, Oh My Pi, Muse, Cursor, Grok Bot and Dots and turns each into a card. One row per session.
final class RealSessionProvider: SessionProviding, @unchecked Sendable {
    /// The list shows five rows at a time and scrolls for the rest.
    var maxProjects = 15
    /// Whether an agent (an Agent id) is switched on in Perch's settings.
    var isEnabled: (String) -> Bool = { Prefs.enabledSources.contains($0) }
    struct Count { let count: Int; let names: [String] }
    private var _counts: [String: Count] = [:]
    /// What the last scan found per agent, before any agent is switched off. Onboarding shows this.
    var counts: [String: Count] { lock.lock(); defer { lock.unlock() }; return _counts }
    /// What the last scan read, so a model can write about it without reading the files again.
    private var _inputs: [String: (digest: SessionDigest, git: GitInfo?)] = [:]
    private let lock = NSLock()
    var inputs: [String: (digest: SessionDigest, git: GitInfo?)] { lock.lock(); defer { lock.unlock() }; return _inputs }
    private let scanner = SessionScanner()

    func parkedProjects() -> [Project] {
        var all = scanner.claude(limit: maxProjects) + scanner.codex(limit: maxProjects) + scanner.opencode(limit: maxProjects) + scanner.pi(limit: maxProjects) + scanner.omp(limit: maxProjects) + scanner.muse(limit: maxProjects) + scanner.cursor(limit: maxProjects)
            + scanner.tasks(limit: maxProjects) + scanner.chats(limit: maxProjects, words: isEnabled(Agent.chat.id))
            + scanner.grokBots(limit: maxProjects) + scanner.dots(limit: maxProjects)
        all.sort { $0.last > $1.last }
        var perApp: [String: (seen: Set<String>, names: [String])] = [:]
        for item in all where !item.project.smallTalk {
            let key = item.project.app, cwd = item.project.cwd ?? item.project.id
            var entry = perApp[key] ?? ([], [])
            if entry.seen.insert(cwd).inserted { entry.names.append(item.project.name) }
            perApp[key] = entry
        }
        lock.lock(); _counts = perApp.mapValues { Count(count: $0.names.count, names: $0.names) }; lock.unlock()
        // Small talk in a terminal takes no real session's place: it is matched to the running agents with the rest (so its
        // process does not claim another session in that folder), then kept only if one of them runs it.
        let on = all.filter { isEnabled($0.project.app) }
        var out = (Array(on.filter { !$0.project.smallTalk }.prefix(maxProjects)) + on.filter(\.project.smallTalk)).sorted { $0.last > $1.last }
        if out.contains(where: { $0.project.terminal }) {
            var projects = out.map(\.project)
            Self.placeTerminalSessions(&projects)
            for i in out.indices { out[i].project = projects[i] }
        }
        out = Array(out.filter { !$0.project.smallTalk || $0.project.pid != nil }.prefix(maxProjects))
        let fresh = Dictionary(out.map { ($0.project.id, (digest: $0.digest, git: $0.git)) }, uniquingKeysWith: { a, _ in a })
        lock.lock(); _inputs = fresh; lock.unlock()
        var projects = out.map(\.project)
        PullRequestState.shared.apply(&projects)
        return projects
    }

    /// For each terminal session: the process running it (if any), the terminal it shows in or would open in, whether that
    /// is inside herdr, and what herdr sees on screen. Where each one runs is remembered, so it can reopen there.
    static func placeTerminalSessions(_ projects: inout [Project]) {
        let (live, viewers) = LiveSessions.scan(), preferred = Terminals.preferred
        FocusProbe.setKnown((live, viewers))
        // herdr's own view of its panes, one query per server.
        var herdr: [String: [String: (status: String, session: String?)]] = [:]
        for h in live { if case .herdr(_, let socket, _) = h.place, herdr[socket] == nil { herdr[socket] = Herdr.agents(socket: socket, bin: h.bin) } }
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
            for _ in 0..<4 where !agentPids.contains(pid) { guard let up = LiveSessions.parent(of: pid), up > 1 else { break }; pid = up }
            guard agentPids.contains(pid), (spoke[pid]?.at ?? .distantPast) < s.at else { continue }
            spoke[pid] = (session, s.at)
        }
        // Oh My Pi keeps its session's owner lock open (`~/.omp/run/session-owners/<id>.lock`): exact, hooks or not.
        let owned = { (h: LiveSessions.Hit) in h.agent == Agent.omp.id ? LiveSessions.ompSession(of: h.pid) : nil }
        let running = Running.match(live.map { Running.Process(agent: $0.agent, cwd: $0.cwd, argv: $0.argv, session: spoke[$0.pid]?.session ?? owned($0) ?? seen($0)?.session, started: $0.started) }, to: projects)
        var places = Prefs.places
        let before = places
        for i in projects.indices where projects[i].terminal {
            let id = projects[i].sessionId ?? projects[i].id
            if let h = running[i].map({ live[$0] }) {
                projects[i].pid = h.pid; projects[i].spot = Spot.key(h.place, tty: h.tty)
                switch h.place {
                case .herdr(_, let socket, let session):
                    projects[i].host = "herdr"; projects[i].via = h.app ?? preferred
                    places[id] = ["kind": "herdr", "socket": socket, "session": session, "workspace": h.place.herdrWorkspace ?? "", "bin": h.bin ?? ""]
                    if let s = seen(h) { projects[i] = HerdrStatus.apply(s.status, to: projects[i]) }
                case .tmux(_, let socket):
                    projects[i].host = "tmux"; projects[i].via = h.app ?? preferred
                    places[id] = ["kind": "tmux", "socket": socket, "session": h.tmuxSession ?? "", "bin": h.bin ?? ""]
                case .cmux:
                    projects[i].via = Terminals.cmux; places[id] = ["kind": "cmux"]
                case .agterm:
                    projects[i].via = Terminals.agterm; places[id] = ["kind": "agterm"]
                case .tab:
                    projects[i].via = h.app ?? preferred
                    if let app = h.app { places[id] = ["kind": "tab", "app": app] }
                }
            } else {
                // Not running: where Pick up would open it again.
                let last = places[id]
                switch last?["kind"] {
                case "herdr":
                    projects[i].host = "herdr"
                    projects[i].via = viewers.first { $0.tmux == nil && $0.session == last?["session"] }?.app ?? preferred
                case "tmux":
                    projects[i].host = "tmux"
                    projects[i].via = viewers.first { $0.tmux == last?["socket"] && $0.session == last?["session"] }?.app ?? preferred
                case "cmux": projects[i].via = Terminals.cmux
                case "agterm": projects[i].via = Terminals.agterm
                default: projects[i].via = preferred
                }
            }
        }
        if places != before {
            if places.count > 300 { places = Dictionary(uniqueKeysWithValues: places.prefix(200).map { ($0.key, $0.value) }) }
            Prefs.places = places
        }
    }
}

/// Where Pick up put you, so Reply knows whether typing would reach the right session.
enum Landing {
    case none
    /// The app now coming forward. `exact`: once it has loaded, its focused input belongs to this session.
    case app(String, exact: Bool)
    /// A new terminal window that is starting the agent (`claude --resume`, `codex resume`) in `cwd`.
    case newTerminal(String, cwd: String, agent: String)
}

/// What "Pick up" does: Claude app sessions open in the Claude app, Codex threads in Codex, Conductor workspaces in Conductor, terminal sessions in their tab,
/// herdr pane, cmux surface or agterm pane, or open again where they last ran.
@MainActor
enum Restorer {
    nonisolated static let claudeApp = "com.anthropic.claudefordesktop", codexApp = "com.openai.codex", opencodeApp = "ai.opencode.desktop", cursorApp = CursorApp.bundle, conductorApp = ConductorApp.bundle, grokBotApp = "com.anysphere.sand"

    /// `done` runs on the main thread once the session is on its way.
    static func resume(_ p: Project, then done: @escaping @MainActor (Landing) -> Void = { _ in }) {
        if p.terminal, let cwd = p.cwd, let id = p.sessionId {
            // Still running: its own tab or pane. Otherwise it opens again where it last ran.
            // AppleScript waits while macOS asks for Automation permission, so it runs off the main thread.
            let agent = p.app, pid = p.pid
            // Words only this session has on screen, for a terminal that cannot be asked which tab it is (Warp).
            let hints = [p.topic, p.asked.map { String($0.split(whereSeparator: \.isNewline).first ?? "").prefix(60) }.map(String.init)].compactMap { $0 }
            DispatchQueue.global(qos: .userInitiated).async {
                let landing: Landing
                let live = LiveSessions.all()
                let hit = live.first { $0.pid == pid && $0.agent == agent } ?? live.first { $0.agent == agent && $0.argv.contains(id) }
                if ProcessInfo.processInfo.environment["PERCH_TRACE"] != nil { NSLog("%@", "Perch pick up: \(agent) \(id.prefix(8)) in \(cwd); running: \(hit.map { "\($0.pid) \($0.place)" } ?? "no")") }
                if let hit, let shown = Terminals.focus(hit, hints: hints) {
                    landing = .app(shown.app, exact: shown.exact)
                } else if hit != nil {
                    // It runs where Perch cannot follow (no terminal app above it). Never start a second copy of it: bring
                    // forward the terminal you used last, which is most of the way there.
                    let app = Terminals.preferred
                    NSRunningApplication.runningApplications(withBundleIdentifier: app).first?.activate()
                    landing = .app(app, exact: false)
                } else {
                    landing = reopen(agent: agent, session: id, cwd: cwd, command: Agent.of(agent).resume(id))
                }
                DispatchQueue.main.async { MainActor.assumeIsolated { done(landing) } }
            }
            return
        }
        // A Conductor workspace opens in Conductor, whichever agent runs in it. Its window is read, so this waits off the main thread.
        if let workspace = p.conductor {
            ConductorApp.bringForward()
            let project = p.name
            DispatchQueue.global(qos: .userInitiated).async {
                let exact = ConductorApp.open(workspace: workspace, project: project)
                DispatchQueue.main.async { MainActor.assumeIsolated { done(.app(conductorApp, exact: exact)) } }
            }
            return
        }
        if p.app == Agent.cursor.id {
            done(.app(cursorApp, exact: CursorWindow.open(chat: p.sessionId, folder: p.cwd)))
            return
        }
        if p.app == "codex" {
            if let id = p.sessionId, let url = URL(string: "codex://threads/\(id)") { NSWorkspace.shared.open(url); done(.app(codexApp, exact: true)) }
            else if let app = AppIcons.url("codex") { NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration()); done(.app(codexApp, exact: false)) }
            else { done(.none) }
            return
        }
        if p.app == Agent.grokbot.id || p.app == Agent.dots.id, let url = link(p) {
            // Their own app, by bundle: two copies of the ChatGPT app can claim `codex://`, and only the newer has Dots.
            let bundle = p.app == Agent.dots.id ? codexApp : grokBotApp
            if let app = AppIcons.url(p.app) { NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) }
            else { NSWorkspace.shared.open(url) }
            done(.app(bundle, exact: true))
            return
        }
        if let url = link(p) {
            // A web page (a cloud Code session) opens in the browser, so a reply is never pasted as if the Claude app showed this session.
            NSWorkspace.shared.open(url); done(.app(claudeApp, exact: url.scheme != "https"))
            return
        }
        done(.none)   // sample data does nothing
    }

    /// Where a session in the Claude app opens: a Code session, a task (what was Cowork), a chat. Nil for anything else.
    nonisolated static func link(_ p: Project) -> URL? {
        switch p.app {
        // A cloud Code session ("session_...") has no link into the app that is known; the web page is the one that works.
        case Agent.cowork.id: return p.desktopSessionId.flatMap { URL(string: $0.hasPrefix("session_") ? "https://claude.ai/code/\($0)" : "claude://claude.ai/cowork/\($0)") }
        case Agent.chat.id: return p.sessionId.flatMap { URL(string: "claude://claude.ai/chat/\($0)") }
        // A Grok Bot bot opens by its id; Dots has one link, to its home (with one dot per account, that is the dot).
        case Agent.grokbot.id: return p.sessionId.flatMap { URL(string: "grokbot://app/v1/agent?id=\($0)") }
        case Agent.dots.id: return URL(string: "codex://dots")
        default: return p.desktopSessionId.flatMap { URL(string: "claude://code/continue?session=\($0)") }
        }
    }

    /// Opens a session that is not running again, where it last ran: a new tab in its herdr workspace, a new window in its
    /// tmux session, the cmux surface that kept it (cmux resumes it), a new cmux workspace, a new agterm session, the
    /// OpenCode app, or a new window of your terminal.
    /// Blocks on the tools it drives, so call it off the main thread.
    /// Where a session opened again in a herdr or tmux client's terminal lands. A tab of that terminal that was only a guess
    /// is no place to type into, so it lands as an app that is not exact.
    nonisolated private static func shown(_ s: Terminals.Shown?, or preferred: String, cwd: String, agent: String) -> Landing {
        guard let s else { return .newTerminal(preferred, cwd: cwd, agent: agent) }
        return s.exact ? .newTerminal(s.app, cwd: cwd, agent: agent) : .app(s.app, exact: false)
    }

    nonisolated static func reopen(agent: String, session id: String, cwd: String, command: String) -> Landing {
        let last = Prefs.places[id], preferred = Terminals.preferred
        if last?["kind"] == "herdr", let socket = last?["socket"], let name = last?["session"] {
            let bin = last?["bin"].flatMap { $0.isEmpty ? nil : $0 }
            if Herdr.running(socket: socket, bin: bin), Herdr.run(command, cwd: cwd, workspace: last?["workspace"], socket: socket, bin: bin) {
                if let v = LiveSessions.scan().viewers.first(where: { $0.tmux == nil && $0.session == name }) { return shown(Terminals.show(v), or: preferred, cwd: cwd, agent: agent) }
                let app = Terminals.open(Herdr.attach(session: name, bin: bin), in: cwd, app: preferred)
                return .newTerminal(app, cwd: cwd, agent: agent)
            }
        }
        if last?["kind"] == "tmux", let socket = last?["socket"] {
            let bin = last?["bin"].flatMap { $0.isEmpty ? nil : $0 }
            if let pane = Tmux.run(command, cwd: cwd, session: last?["session"], socket: socket, bin: bin) {
                // Shown in the client already on that session, else the one used last; with none, a terminal attaches to it.
                if let c = Tmux.ask(socket: socket, bin: Tmux.bin(bin))?.viewer(of: pane), Tmux.show(pane: pane, socket: socket, client: c.tty, bin: bin) {
                    return shown(Terminals.show(LiveSessions.viewer(c, socket: socket, bin: Tmux.bin(bin))), or: preferred, cwd: cwd, agent: agent)
                }
                let app = Terminals.open(Tmux.attach(pane: pane, socket: socket, bin: bin), in: cwd, app: preferred)
                return .newTerminal(app, cwd: cwd, agent: agent)
            }
        }
        if Cmux.app != nil {
            if let held = Cmux.heldSurface(agent: agent, session: id), Cmux.focus(workspace: held.workspace, surface: held.surface) {
                return .newTerminal(Terminals.cmux, cwd: cwd, agent: agent)
            }
            if last?["kind"] == "cmux" { Terminals.open(command, in: cwd, app: Terminals.cmux); return .newTerminal(Terminals.cmux, cwd: cwd, agent: agent) }
        }
        // Terminals.open falls back to Terminal when agterm cannot make the session.
        if last?["kind"] == "agterm" {
            let app = Terminals.open(command, in: cwd, app: Terminals.agterm)
            return .newTerminal(app, cwd: cwd, agent: agent)
        }
        // An OpenCode session that never ran in a terminal Perch saw may be the desktop app's.
        if agent == "opencode", last == nil, let app = NSRunningApplication.runningApplications(withBundleIdentifier: opencodeApp).first {
            app.activate()
            return .app(opencodeApp, exact: false)
        }
        let app = Terminals.open(command, in: cwd, app: preferred)
        return .newTerminal(app, cwd: cwd, agent: agent)
    }
}
