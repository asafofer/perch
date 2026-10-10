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
        var out = Array(all.filter { isEnabled($0.project.app) }.prefix(maxProjects))
        // A terminal session shows the terminal it runs in, or the one Pick up would open it in.
        if out.contains(where: { $0.project.terminal }) {
            let live = LiveSessions.all(), preferred = Terminals.preferred
            for i in out.indices where out[i].project.terminal {
                let p = out[i].project
                out[i].project.via = live.first { $0.agent == p.app && $0.cwd == p.cwd }?.app ?? preferred
            }
        }
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
    /// A new terminal window that is starting the agent (`claude --resume`, `codex resume`) in `cwd`.
    case newTerminal(String, cwd: String, agent: String)
}

/// What "Pick up" does: Claude app sessions open in the Claude app, Codex threads in Codex.
@MainActor
enum Restorer {
    nonisolated static let claudeApp = "com.anthropic.claudefordesktop", codexApp = "com.openai.codex"

    /// `done` runs on the main thread once the session is on its way.
    static func resume(_ p: Project, then done: @escaping @MainActor (Landing) -> Void = { _ in }) {
        if p.terminal, let cwd = p.cwd, let id = p.sessionId {
            // Still running: its own tab. Otherwise it resumes in a new window of the terminal you use.
            // AppleScript waits while macOS asks for Automation permission, so it runs off the main thread.
            let agent = p.app, preferred = Terminals.preferred
            DispatchQueue.global(qos: .userInitiated).async {
                let landing: Landing
                let live = LiveSessions.all(), hits = live.filter { $0.agent == agent && $0.cwd == cwd }
                if ProcessInfo.processInfo.environment["PERCH_TRACE"] != nil { NSLog("Perch pick up: \(agent) in \(cwd); live: \(live.map { "\($0.agent) \($0.cwd) \($0.app ?? "-")" })") }
                if let hit = hits.first, let app = Terminals.focus(hit) {
                    landing = .app(app, exact: hits.count == 1)   // two sessions in one folder: the tab may be the other one
                } else {
                    Terminals.open(agent == "codex" ? "codex resume \(id)" : "claude --resume \(id)", in: cwd, app: preferred)
                    landing = .newTerminal(preferred, cwd: cwd, agent: agent)
                }
                DispatchQueue.main.async { MainActor.assumeIsolated { done(landing) } }
            }
            return
        }
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
