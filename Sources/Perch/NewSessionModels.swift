import Foundation
import PerchCore

/// The models a new session can start on, for each terminal agent: its default from its own config, its own list
/// (Claude Code's names, Codex's picker), the ones used on this Mac, and what is found by typing. OpenCode is asked in the
/// background (`opencode models` takes a moment, its database is read once) and its answer kept for ten minutes.
enum NewSessionModels {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var opencode: (list: [String], used: [String], at: Date) = ([], [], .distantPast)

    static func list(agent: String) -> [NewSession.Model] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let configured: String? = switch agent {
        case "claude": (try? Data(contentsOf: home.appendingPathComponent(".claude/settings.json"))).flatMap(NewSession.claudeDefault)
        case "codex": (try? String(contentsOf: home.appendingPathComponent(".codex/config.toml"), encoding: .utf8)).flatMap(NewSession.codexDefault)
        default: nil
        }
        let catalog = agent == "codex" ? (try? Data(contentsOf: home.appendingPathComponent(".codex/models_cache.json"))).map(NewSession.codexCatalog) ?? [] : []
        lock.lock(); let oc = opencode; lock.unlock()
        let used = Prefs.usedModels(agent) + (agent == "opencode" ? oc.used : [])
        return NewSession.models(agent: agent, configured: configured, catalog: catalog, available: agent == "opencode" ? oc.list : [], used: used)
    }

    /// Asks OpenCode for its models when the last answer is older than ten minutes. `changed` runs on the main thread when
    /// the list is not what it was. A provider that does not answer is given up on after 15 s.
    static func refreshOpencode(bin: String, changed: @escaping @MainActor () -> Void) {
        lock.lock(); let fresh = Date().timeIntervalSince(opencode.at) < 600; if !fresh { opencode.at = Date() }; lock.unlock()
        guard !fresh else { return }
        DispatchQueue.global(qos: .utility).async {
            let p = Process(); p.executableURL = URL(fileURLWithPath: bin); p.arguments = ["models"]
            let out = Pipe(); p.standardOutput = out; p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return }
            DispatchQueue.global().asyncAfter(deadline: .now() + 15) { if p.isRunning { p.terminate() } }
            let data = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
            let list = NewSession.opencodeModels(String(decoding: data, as: UTF8.self))
            let db = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share/opencode/opencode.db")
            let used = OpenCodeStore(url: db)?.usedModels() ?? []
            lock.lock(); let differs = list != opencode.list || used != opencode.used; opencode.list = list.isEmpty ? opencode.list : list; opencode.used = used; lock.unlock()
            if differs { DispatchQueue.main.async { MainActor.assumeIsolated { changed() } } }
        }
    }
}
