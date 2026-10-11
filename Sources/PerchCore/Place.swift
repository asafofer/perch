import Foundation

/// Where a running agent lives, read from its environment. herdr and cmux put their own variables in every process they run.
public enum Place: Equatable, Sendable {
    /// A pane in a herdr server. `socket` reaches that server; `session` is its name ("default" for the usual one).
    case herdr(pane: String, socket: String, session: String)
    /// A surface (a tab or split) in cmux.
    case cmux(workspace: String, surface: String)
    /// A terminal's own tab.
    case tab

    /// Innermost first: a herdr server started from a cmux tab passes that tab's variables to every pane, so herdr's win.
    public static func from(environment env: [String: String]) -> Place {
        if let pane = env["HERDR_PANE_ID"], !pane.isEmpty, let socket = env["HERDR_SOCKET_PATH"], !socket.isEmpty {
            return .herdr(pane: pane, socket: socket, session: env["HERDR_SESSION"].flatMap { $0.isEmpty ? nil : $0 } ?? "default")
        }
        if let s = env["CMUX_SURFACE_ID"], !s.isEmpty, let w = env["CMUX_WORKSPACE_ID"], !w.isEmpty { return .cmux(workspace: w, surface: s) }
        return .tab
    }

    /// The herdr workspace a pane belongs to: "w2" of "w2:p1".
    public var herdrWorkspace: String? {
        guard case .herdr(let pane, _, _) = self else { return nil }
        return pane.split(separator: ":").first.map(String.init)
    }
}

/// A process's executable, arguments and environment, as `sysctl(KERN_PROCARGS2)` returns them: the argument count, the
/// executable path, padding, then each argument and each `KEY=value`, every one ended by a zero byte.
public struct ProcessArgs: Equatable, Sendable {
    public let executable: String
    public let argv: [String]
    public let environment: [String: String]
    public init(executable: String, argv: [String], environment: [String: String]) { self.executable = executable; self.argv = argv; self.environment = environment }

    public static func parse(_ data: Data) -> ProcessArgs? {
        guard data.count > 4 else { return nil }
        let argc = Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: Int32.self) })
        var i = data.startIndex + 4
        func next() -> String? {
            guard i < data.endIndex, let end = data[i...].firstIndex(of: 0) else { return nil }
            let s = String(decoding: data[i..<end], as: UTF8.self)
            i = end + 1
            return s
        }
        guard let exe = next() else { return nil }
        while i < data.endIndex, data[i] == 0 { i += 1 }   // padding after the path
        var argv: [String] = []
        for _ in 0..<max(0, argc) { guard let a = next() else { break }; argv.append(a) }
        // A process that renamed itself (node's process.title) leaves empty strings where its arguments were.
        var env: [String: String] = [:]
        while let e = next() {
            guard !e.isEmpty, let eq = e.firstIndex(of: "=") else { continue }
            let key = String(e[..<eq])
            if env[key] == nil { env[key] = String(e[e.index(after: eq)...]) }
        }
        return ProcessArgs(executable: exe, argv: argv, environment: env)
    }
}

/// Which session each running agent is.
public enum Running {
    public struct Process: Equatable, Sendable {
        public let agent: String, cwd: String, argv: [String]
        /// The session id something else reported for it (herdr's own integration).
        public let session: String?
        /// When the process started. A session quiet since before then is not the one it runs.
        public let started: Date?
        public init(agent: String, cwd: String, argv: [String], session: String? = nil, started: Date? = nil) {
            self.agent = agent; self.cwd = cwd; self.argv = argv; self.session = session; self.started = started
        }
    }

    /// Project index to process index. A process that names its session is that session: its command
    /// (`claude --resume <id>`, `pi --session <id>`, `opencode -s <id>`, `codex resume <id>`), Perch's own hooks, or herdr.
    /// Any other owns the sessions of its agent in its folder begun between its start and the next such process's start;
    /// with several side by side each has the first it began, alone it has the one active last (after /clear or /new).
    /// A freshly started agent with nothing said yet has none.
    public static func match(_ processes: [Process], to projects: [Project]) -> [Int: Int] {
        var out: [Int: Int] = [:], taken = Set<Int>()
        for (h, p) in processes.enumerated() {
            guard let i = projects.indices.first(where: { k in
                projects[k].app == p.agent && out[k] == nil && projects[k].sessionId.map { id in p.session == id || p.argv.contains(id) } == true
            }) else { continue }
            out[i] = h; taken.insert(h)
        }
        let start = { (h: Int) in processes[h].started ?? .distantPast }
        let active = { (i: Int) in projects[i].lastActive ?? .distantPast }
        let rest = processes.indices.filter { !taken.contains($0) }.sorted { start($0) < start($1) }
        for h in rest {
            let p = processes[h], from = start(h)
            let peers = rest.filter { processes[$0].agent == p.agent && processes[$0].cwd == p.cwd }
            let until = peers.map(start).filter { $0 > from }.min() ?? .distantFuture
            let same = projects.indices.filter { projects[$0].app == p.agent && projects[$0].cwd == p.cwd && out[$0] == nil && active($0) >= from.addingTimeInterval(-5) }
            let begun = { (i: Int) in projects[i].startedAt ?? .distantPast }
            let mine = same.filter { begun($0) >= from.addingTimeInterval(-2) && begun($0) < until.addingTimeInterval(-2) }
            let pick: Int?
            if mine.isEmpty { pick = same.filter { begun($0) < from }.max { active($0) < active($1) } }   // a session it continued
            else if peers.count > 1 { pick = mine.min { begun($0) < begun($1) } }
            else { pick = mine.max { active($0) < active($1) } }
            if let i = pick { out[i] = h }
        }
        return out
    }
}

/// What herdr says about an agent in one of its panes, when hooks say nothing: it reads the screen, so it knows when
/// an agent shows an approval or a question even without hooks.
public enum HerdrStatus {
    public static func apply(_ status: String, to p: Project) -> Project {
        let a = Agent.of(p.app)
        var q = p
        switch status {
        case "blocked": q.agents = [AgentStatus(kind: .needsYou, text: "\(a.short) is waiting for you", app: p.app)]
        case "working": q.agents = [AgentStatus(kind: .running, text: "\(a.name) is working", app: p.app)]
        case "done", "idle":
            // The transcript guessed it was still at work; herdr sees it ready for you.
            guard p.status.kind == "running" || p.status.kind == "attention" && (p.ask == nil || p.ask?.transcriptAt != nil) else { return p }
            q.agents = [AgentStatus(kind: .done, text: "\(a.short) finished", app: p.app)]; q.now = nil; q.ask = nil
        default: return p
        }
        return q
    }
}
