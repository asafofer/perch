import Foundation

/// Starting a new session from the notch: which agents can start one here, the folders to offer, what to start on, the
/// command a terminal agent runs, and how to tell that the new session really began.
public enum NewSession {
    /// An agent to start a session with, and where: the Claude or Codex app, or an agent in your terminal.
    public struct Choice: Equatable, Sendable {
        /// "claude" (the Claude app), "claude-code", "codex" (the Codex app), "codex-cli", "opencode", "pi".
        public let id: String
        /// The agent: "claude", "codex", "opencode", "pi".
        public let agent: String
        /// It runs in your terminal, not in the agent's own app.
        public let terminal: Bool
        public let name: String
        public init(id: String, agent: String, terminal: Bool, name: String) { self.id = id; self.agent = agent; self.terminal = terminal; self.name = name }
    }

    /// What is on this Mac, in a fixed order: the apps first, each followed by its own command line tool.
    public static func choices(claudeApp: Bool, codexApp: Bool, commands: Set<String>) -> [Choice] {
        var out: [Choice] = []
        if claudeApp { out.append(Choice(id: "claude", agent: "claude", terminal: false, name: "Claude")) }
        if commands.contains("claude") { out.append(Choice(id: "claude-code", agent: "claude", terminal: true, name: "Claude Code")) }
        if codexApp { out.append(Choice(id: "codex", agent: "codex", terminal: false, name: "Codex")) }
        if commands.contains("codex") { out.append(Choice(id: "codex-cli", agent: "codex", terminal: true, name: codexApp ? "Codex CLI" : "Codex")) }
        if commands.contains("opencode") { out.append(Choice(id: "opencode", agent: "opencode", terminal: true, name: "OpenCode")) }
        if commands.contains("pi") { out.append(Choice(id: "pi", agent: "pi", terminal: true, name: "pi")) }
        return out
    }

    /// The choice that starts a session like this one: the same agent, in its app or in a terminal as it ran.
    public static func choiceId(for p: Project) -> String {
        switch (p.app, p.terminal) {
        case ("claude", false): "claude"
        case ("claude", true): "claude-code"
        case ("codex", false): "codex"
        case ("codex", true): "codex-cli"
        default: p.app
        }
    }

    public struct Folder: Equatable, Sendable {
        public let name: String
        public let path: String
        public let lastActive: Date?
        /// How long ago, as the list says it ("4m", "2h", "3d").
        public let away: String
        public init(name: String, path: String, lastActive: Date?, away: String = "") { self.name = name; self.path = path; self.lastActive = lastActive; self.away = away }
    }

    /// The folders sessions ran in, newest first, each once. A worktree counts as its repository; chats started without a
    /// folder (the Claude app's scratch workspaces, Codex's dated ones) are not folders to offer.
    public static func folders(_ projects: [Project]) -> [Folder] {
        var seen: [String: Int] = [:], out: [Folder] = []
        let sorted = projects.sorted { ($0.lastActive ?? .distantPast) > ($1.lastActive ?? .distantPast) }
        for p in sorted {
            guard let cwd = p.cwd, !cwd.isEmpty, !Recap.isFolderless(cwd) else { continue }
            let path = root(cwd)
            if seen[path] != nil { continue }
            seen[path] = out.count
            out.append(Folder(name: (path as NSString).lastPathComponent, path: path, lastActive: p.lastActive, away: String(p.away.split(separator: " ").first ?? "")))
        }
        return out
    }

    /// A worktree's repository: "/repo/.claude/worktrees/x" and "/repo/.worktrees/x" are "/repo".
    public static func root(_ cwd: String) -> String {
        for marker in ["/.claude/worktrees/", "/.worktrees/", "/.codex/worktrees/"] {
            if let r = cwd.range(of: marker) { return String(cwd[..<r.lowerBound]) }
        }
        return cwd.hasSuffix("/") && cwd.count > 1 ? String(cwd.dropLast()) : cwd
    }

    /// What it starts on: the session you are looking at (the row you were on, or the session in front of you), else the
    /// agent and folder you started with last, else the first agent and the newest folder.
    public static func defaults(looking: Project?, lastChoice: String?, lastFolder: String?, choices: [Choice], folders: [Folder]) -> (choice: String?, folder: String?) {
        let ids = Set(choices.map(\.id)), paths = Set(folders.map(\.path))
        if let p = looking {
            let c = choiceId(for: p), f = p.cwd.map(root)
            return (ids.contains(c) ? c : lastChoice.flatMap { ids.contains($0) ? $0 : nil } ?? choices.first?.id,
                    f.flatMap { paths.contains($0) ? $0 : nil })
        }
        return (lastChoice.flatMap { ids.contains($0) ? $0 : nil } ?? choices.first?.id,
                lastFolder.flatMap { paths.contains($0) ? $0 : nil } ?? folders.first?.path)
    }

    /// The command a terminal agent starts with, your words as its first message. Claude Code and pi are given the new
    /// session's id, so Perch knows exactly which session to wait for.
    public static func command(agent: String, prompt: String, sessionId: String? = nil) -> String {
        let q = quote(prompt)
        switch agent {
        case "claude": return "claude" + (sessionId.map { " --session-id \($0)" } ?? "") + " " + q
        case "codex": return "codex " + q
        case "opencode": return "opencode --prompt " + q
        case "pi": return "pi" + (sessionId.map { " --session-id \($0)" } ?? "") + " " + q
        default: return q
        }
    }
    static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    /// The new session, once the scan finds it: one Perch had not seen before, of that agent, run where it was asked for
    /// (in its app or a terminal), in that folder (or a worktree of it), and begun after it was started. With an id, only that one.
    public static func started(in projects: [Project], choice: Choice, folder: String?, since: Date, known: Set<String>, sessionId: String? = nil) -> Project? {
        projects.first { p in
            if let sessionId { return p.sessionId == sessionId }
            guard !known.contains(p.id), p.app == choice.agent, p.terminal == choice.terminal else { return false }
            if let folder, let cwd = p.cwd, root(cwd) != folder { return false }
            let began = p.startedAt ?? p.lastActive ?? .distantPast
            return began >= since.addingTimeInterval(-5)
        }
    }

    /// How long to wait for the new session to show before saying it did not start.
    public static let waits: TimeInterval = 40
}
