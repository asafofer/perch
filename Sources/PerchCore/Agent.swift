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
    /// Read from the start. Off until you switch it on: Claude chats, which are not coding work and can be personal.
    public var onByDefault = true

    public static let claude = Agent(id: "claude", name: "Claude Code", short: "Claude", resumeCommand: "claude --resume", answersFromNotch: true)
    public static let codex = Agent(id: "codex", name: "Codex", short: "Codex", resumeCommand: "codex resume", answersFromNotch: false)
    public static let opencode = Agent(id: "opencode", name: "OpenCode", short: "OpenCode", resumeCommand: "opencode -s", answersFromNotch: true)
    public static let pi = Agent(id: "pi", name: "pi", short: "pi", resumeCommand: "pi --session", answersFromNotch: false)
    /// Cowork and chats live in the Claude app: they open there, and have no command and no hooks.
    public static let cowork = Agent(id: "cowork", name: "Cowork", short: "Claude", resumeCommand: "", answersFromNotch: false)
    public static let chat = Agent(id: "chat", name: "Claude chats", short: "Claude", resumeCommand: "", answersFromNotch: false, onByDefault: false)
    public static let all = [claude, codex, opencode, pi, cowork, chat]

    /// The agent with that id; Claude for anything unknown (sample data).
    public static func of(_ id: String) -> Agent { all.first { $0.id == id } ?? claude }

    /// `claude --resume <id>`, `pi --session <id>`. With `prompt`, your words go in as its first message.
    public func resume(_ session: String, prompt: String? = nil) -> String {
        guard let prompt else { return "\(resumeCommand) \(session)" }
        let quoted = "'" + prompt.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return id == "opencode" ? "\(resumeCommand) \(session) --prompt \(quoted)" : "\(resumeCommand) \(session) \(quoted)"
    }

    /// Which agent a process is, from its executable path and argv[0]. pi, and Claude Code installed with npm, run under
    /// node or bun and name themselves in argv[0].
    /// The native Claude installer runs ~/.local/share/claude/versions/<version>; Claude Code 2.1 from npm runs its native
    /// binary as the package's bin/claude.exe. Nil for anything else.
    public static func recognise(executable: String, argv0: String?) -> Agent? {
        let name = (executable as NSString).lastPathComponent
        if executable.contains("/claude/versions/") || name == "claude" || name == "claude.exe" { return .claude }
        if name == "codex" || name.hasPrefix("codex-") { return .codex }
        if name == "opencode" { return .opencode }
        if name == "pi" { return .pi }
        if ["node", "bun"].contains(name), let a = argv0.map({ ($0 as NSString).lastPathComponent }) {
            if a == "pi" { return .pi }
            if a == "claude" { return .claude }
        }
        return nil
    }

    /// Worth reading a process's arguments for: an executable `recognise` could take for an agent (node and bun by argv[0]).
    public static func mayBe(_ executable: String) -> Bool {
        let name = (executable as NSString).lastPathComponent
        return ["claude", "claude.exe", "codex", "opencode", "pi", "node", "bun"].contains(name) || name.hasPrefix("codex-") || executable.contains("/claude/versions/")
    }
}
