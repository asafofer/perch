import AppKit
import PerchCore

/// Reads the recent sessions of the Claude app and Codex and turns each into a card. One row per session.
final class RealSessionProvider: SessionProviding, @unchecked Sendable {
    /// The list shows five rows at a time and scrolls for the rest.
    var maxProjects = 15
    /// Whether an agent ("claude", "codex") is switched on in Perch's settings.
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
        var all = scanner.claude(limit: maxProjects) + scanner.codex(limit: maxProjects)
        all.sort { $0.last > $1.last }
        var perApp: [String: (seen: Set<String>, names: [String])] = [:]
        for item in all {
            let key = item.project.app, cwd = item.project.cwd ?? item.project.id
            var entry = perApp[key] ?? ([], [])
            if entry.seen.insert(cwd).inserted { entry.names.append(item.project.name) }
            perApp[key] = entry
        }
        lock.lock(); _counts = perApp.mapValues { Count(count: $0.names.count, names: $0.names) }; lock.unlock()
        let out = Array(all.filter { isEnabled($0.project.app) }.prefix(maxProjects))
        let fresh = Dictionary(out.map { ($0.project.id, (digest: $0.digest, git: $0.git)) }, uniquingKeysWith: { a, _ in a })
        lock.lock(); _inputs = fresh; lock.unlock()
        return out.map(\.project)
    }
}

/// Where Pick up put you, so Reply knows whether typing would reach the right session.
enum Landing {
    case none
    /// The app now coming forward. `exact`: once it has loaded, its focused input belongs to this session.
    case app(String, exact: Bool)
}

/// What "Pick up" does: Claude app sessions open in the Claude app, Codex threads in Codex.
@MainActor
enum Restorer {
    static let claudeApp = "com.anthropic.claudefordesktop", codexApp = "com.openai.codex"

    /// `done` runs on the main thread once the session is on its way.
    static func resume(_ p: Project, then done: @escaping @MainActor (Landing) -> Void = { _ in }) {
        if p.app == "codex" {
            if let id = p.sessionId, let url = URL(string: "codex://threads/\(id)") { NSWorkspace.shared.open(url); done(.app(codexApp, exact: true)) }
            else if let app = AppIcons.url("codex") { NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration()); done(.app(codexApp, exact: false)) }
            else { done(.none) }
            return
        }
        if let id = p.desktopSessionId, let url = URL(string: "claude://code/continue?session=\(id)") {
            NSWorkspace.shared.open(url); done(.app(claudeApp, exact: true))
            return
        }
        done(.none)   // sample data does nothing
    }
}
