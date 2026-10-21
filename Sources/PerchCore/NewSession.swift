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
    /// session's id, so Perch knows exactly which session to wait for. `model`: the one chosen, else the agent's own default.
    public static func command(agent: String, prompt: String, sessionId: String? = nil, model: String? = nil) -> String {
        let q = quote(prompt), m = model.flatMap { $0.isEmpty || !takesModel(agent) ? nil : quote($0) }
        switch agent {
        case "claude": return "claude" + (m.map { " --model \($0)" } ?? "") + (sessionId.map { " --session-id \($0)" } ?? "") + " " + q
        case "codex": return "codex" + (m.map { " -m \($0)" } ?? "") + " " + q
        case "opencode": return "opencode" + (m.map { " --model \($0)" } ?? "") + " --prompt " + q
        case "pi": return "pi" + (sessionId.map { " --session-id \($0)" } ?? "") + " " + q
        default: return q
        }
    }

    /// A model to start a session on. `id` is what the agent is given; empty is its own default, whose name `note` says.
    public struct Model: Equatable, Sendable {
        public let id: String, name: String, note: String
        public init(id: String, name: String, note: String = "") { self.id = id; self.name = name; self.note = note }
    }

    /// The terminal agents a model can be chosen for. The apps' links take none, and pi is left to its own default.
    public static func takesModel(_ agent: String) -> Bool { ["claude", "codex", "opencode"].contains(agent) }

    /// Claude Code's own names for its latest models (`claude --model fable`): there from the start, a model you have
    /// never used among them, and never stale, since Claude Code itself says which model each stands for.
    public static let claudeAliases = ["fable", "opus", "sonnet", "haiku"]

    /// What to offer for an agent: its own default first (named by its config), then Claude Code's names or the models
    /// OpenCode lists, then ones you typed before, each once. Empty for an agent that takes no model.
    public static func models(agent: String, configured: String?, available: [String] = [], used: [String] = []) -> [Model] {
        guard takesModel(agent) else { return [] }
        var out = [Model(id: "", name: "Default", note: configured ?? "")], seen: Set<String> = [""]
        let named = agent == "claude" ? claudeAliases : agent == "opencode" ? available : []
        for id in named + used where !id.isEmpty && seen.insert(id.lowercased()).inserted { out.append(Model(id: id, name: id)) }
        return out
    }

    /// Claude Code's default model: `"model"` in ~/.claude/settings.json.
    public static func claudeDefault(settings: Data) -> String? {
        guard let o = try? JSONSerialization.jsonObject(with: settings) as? [String: Any], let m = o["model"] as? String, !m.isEmpty else { return nil }
        return m
    }

    /// Codex's default model: the top-level `model = "..."` in ~/.codex/config.toml, before any [table].
    public static func codexDefault(config: String) -> String? {
        for raw in config.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { return nil }
            guard line.hasPrefix("model"), let eq = line.firstIndex(of: "=") else { continue }
            guard line[..<eq].trimmingCharacters(in: .whitespaces) == "model" else { continue }
            let v = line[line.index(after: eq)...].split(separator: "#", maxSplits: 1).first.map(String.init) ?? ""
            let m = v.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return m.isEmpty ? nil : m
        }
        return nil
    }

    /// What `opencode models` prints: one `provider/model` a line.
    public static func opencodeModels(_ output: String) -> [String] {
        output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.contains("/") && !$0.contains(" ") }
    }
    static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    /// The new session, once the scan finds it: one Perch had not seen before, of that agent, run where it was asked for
    /// (in its app or a terminal), in that folder (or a worktree of it), and begun after it was started. With an id, only that one.
    /// anyFolder: the app asked you to confirm first, where you can also pick another folder, so a new session of that
    /// agent begun since counts wherever it runs.
    public static func started(in projects: [Project], choice: Choice, folder: String?, since: Date, known: Set<String>, sessionId: String? = nil, anyFolder: Bool = false) -> Project? {
        projects.first { p in
            if let sessionId { return p.sessionId == sessionId }
            guard !known.contains(p.id), p.app == choice.agent, p.terminal == choice.terminal else { return false }
            if !anyFolder, let folder, let cwd = p.cwd, root(cwd) != folder { return false }
            let began = p.startedAt ?? p.lastActive ?? .distantPast
            return began >= since.addingTimeInterval(-5)
        }
    }

    /// How long to wait for the new session to show before saying it did not start.
    public static let waits: TimeInterval = 40
}
