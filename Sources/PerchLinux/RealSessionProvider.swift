import CPerchLinux
import Foundation
import PerchCore

// OWNER: the sessions agent. STUB.
/// Runs the SessionScanner (no Claude app or Codex app on Linux: terminal sessions of every agent), places terminal
/// sessions where they run (LiveSessions), keeps per-agent counts.
final class RealSessionProvider: SessionProviding, @unchecked Sendable {
    var maxProjects = 15
    var isEnabled: (String) -> Bool = { Prefs.enabledSources.contains($0) }
    struct Count { let count: Int; let names: [String] }
    var counts: [String: Count] { [:] }
    func parkedProjects() -> [Project] { [] }
}

/// Where Pick up put you, so Reply knows whether typing would reach the right session.
enum Landing {
    case none
    case app(String, exact: Bool)
    case newTerminal(String, cwd: String, agent: String)
}

/// What Pick up does on Linux: a running terminal session goes back to where it runs; a stopped one opens again where it
/// last ran (Prefs.places), else in the terminal you used last, with its agent's resume command.
@MainActor
enum Restorer {
    static func resume(_ p: Project, then done: @escaping @MainActor (Landing) -> Void = { _ in }) { done(.none) }
    nonisolated static func reopen(agent: String, session id: String, cwd: String, command: String) -> Landing { .none }
}
