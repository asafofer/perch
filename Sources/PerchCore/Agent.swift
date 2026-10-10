import Foundation

/// A coding agent Perch reads: what it is called, how to resume one of its sessions, and how to spot it running.
public struct Agent: Equatable, Sendable {
    /// "claude", "codex", "opencode", "pi". Also the key of its icon in the page.
    public let id: String
    /// "Claude Code", "OpenCode".
    public let name: String
    /// The name in a sentence: "Claude wants to run a command", "pi finished".
    public let short: String
    /// The terminal command that resumes a session, without the id.
    let resumeCommand: String
    /// Perch can answer what it asks from the notch: allow, deny, a question's choices.
    public let answersFromNotch: Bool

    public static let claude = Agent(id: "claude", name: "Claude Code", short: "Claude", resumeCommand: "claude --resume", answersFromNotch: true)
    public static let codex = Agent(id: "codex", name: "Codex", short: "Codex", resumeCommand: "codex resume", answersFromNotch: false)
    public static let opencode = Agent(id: "opencode", name: "OpenCode", short: "OpenCode", resumeCommand: "opencode -s", answersFromNotch: true)
    public static let pi = Agent(id: "pi", name: "pi", short: "pi", resumeCommand: "pi --session", answersFromNotch: false)
    public static let all = [claude, codex, opencode, pi]

    /// The agent with that id; Claude for anything unknown (sample data).
    public static func of(_ id: String) -> Agent { all.first { $0.id == id } ?? claude }

    /// `claude --resume <id>`, `pi --session <id>`.
    public func resume(_ session: String) -> String { "\(resumeCommand) \(session)" }

    /// Which agent a process is, from its executable path and argv[0]. pi runs under node or bun and names itself in argv[0].
    /// The native Claude installer runs ~/.local/share/claude/versions/<version>. Nil for anything else.
    public static func recognise(executable: String, argv0: String?) -> Agent? {
        let name = (executable as NSString).lastPathComponent
        if executable.contains("/claude/versions/") || name == "claude" { return .claude }
        if name == "codex" || name.hasPrefix("codex-") { return .codex }
        if name == "opencode" { return .opencode }
        if name == "pi" { return .pi }
        if ["node", "bun"].contains(name), let a = argv0.map({ ($0 as NSString).lastPathComponent }), a == "pi" { return .pi }
        return nil
    }
}
