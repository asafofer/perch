import AppKit
import PerchCore

/// Reads the newest session of each recent project from ~/.claude/projects and turns it into a card.
final class RealSessionProvider: SessionProviding, @unchecked Sendable {
    var maxProjects = 5
    /// Whether an agent ("claude", "codex") is switched on in Perch's settings.
    var isEnabled: (String) -> Bool = { Prefs.enabledSources.contains($0) }
    struct Count { let count: Int; let names: [String] }
    private var _counts: [String: Count] = [:]
    /// What the last scan found per agent, before any agent is switched off. Onboarding shows this.
    var counts: [String: Count] { lock.lock(); defer { lock.unlock() }; return _counts }
    var maxAgeDays = 14
    /// What the last scan read, so a model can write about it without reading the files again.
    private var _inputs: [String: (digest: SessionDigest, git: GitInfo?)] = [:]
    private let lock = NSLock()
    var inputs: [String: (digest: SessionDigest, git: GitInfo?)] { lock.lock(); defer { lock.unlock() }; return _inputs }

    func parkedProjects() -> [Project] {
        var all = claudeProjects() + codexProjects()
        all.sort { $0.last > $1.last }
        var perApp: [String: (seen: Set<String>, names: [String])] = [:]
        for item in all {
            let key = item.project.app, cwd = item.project.cwd ?? item.project.id
            var entry = perApp[key] ?? ([], [])
            if entry.seen.insert(cwd).inserted { entry.names.append(item.project.name) }
            perApp[key] = entry
        }
        lock.lock(); _counts = perApp.mapValues { Count(count: $0.names.count, names: $0.names) }; lock.unlock()
        all = all.filter { isEnabled($0.project.app) }
        var seen = Set<String>(), out: [Project] = []
        var fresh: [String: (digest: SessionDigest, git: GitInfo?)] = [:]
        for item in all {
            guard let cwd = item.project.cwd, !seen.contains(cwd) else { continue }
            seen.insert(cwd); out.append(item.project)
            fresh[item.project.id] = (item.digest, item.git)
            if out.count == maxProjects { break }
        }
        lock.lock(); _inputs = fresh; lock.unlock()
        return out
    }

    /// Reading a session tail is the slow part, so a file is only read again when it changed.
    private var digestCache: [String: (mtime: Date, digest: SessionDigest)] = [:]
    private var gitCache: [String: (at: Date, info: GitInfo?, branch: String?)] = [:]

    private func cachedDigest(_ url: URL, mtime: Date, parse: ([String]) -> SessionDigest) -> SessionDigest? {
        lock.lock(); let hit = digestCache[url.path]; lock.unlock()
        if let hit, hit.mtime == mtime { return hit.digest }
        guard let d = Self.digest(of: url, parse: parse) else { return nil }
        lock.lock(); digestCache[url.path] = (mtime, d); lock.unlock()
        return d
    }

    /// Git state changes slowly next to a conversation, so it is looked up at most every 30 seconds per folder.
    private func cachedGit(_ cwd: String, withBranch: Bool = false) -> (info: GitInfo?, branch: String?) {
        lock.lock(); let hit = gitCache[cwd]; lock.unlock()
        if let hit, Date().timeIntervalSince(hit.at) < 30, !withBranch || hit.branch != nil { return (hit.info, hit.branch) }
        let info = Self.git(at: cwd), branch = withBranch ? Self.branch(at: cwd) : hit?.branch
        lock.lock(); gitCache[cwd] = (Date(), info, branch); lock.unlock()
        return (info, branch)
    }

    typealias Found = (project: Project, digest: SessionDigest, git: GitInfo?, last: Date)

    private func usable(_ cwd: String) -> Bool {
        !cwd.contains("/scratch-workspaces/") && !cwd.contains("/scratchpad") && !cwd.hasPrefix("/private/tmp")
            && !cwd.hasPrefix("/tmp") && !cwd.hasPrefix("/var/") && FileManager.default.fileExists(atPath: cwd)
    }

    // MARK: Claude Code (~/.claude/projects/*/*.jsonl)
    private func claudeProjects() -> [Found] {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        guard let dirs = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        let cutoff = Date().addingTimeInterval(-Double(maxAgeDays) * 86_400)
        // The newest few sessions of each folder, newest folder first. A headless run (`claude -p`) or an empty session
        // can be the newest file, so the next one down stands in for it.
        var folders: [[(url: URL, mtime: Date)]] = []
        for dir in dirs {
            guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            let recent = files.filter { $0.pathExtension == "jsonl" }
                .compactMap { u -> (url: URL, mtime: Date)? in (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate).map { (u, $0) } }
                .filter { $0.mtime > cutoff }
                .sorted { $0.mtime > $1.mtime }
            if !recent.isEmpty { folders.append(Array(recent.prefix(3))) }
        }
        folders.sort { $0[0].mtime > $1[0].mtime }

        var seen = Set<String>(), out: [Found] = []
        let now = Date()
        let desktop = DesktopSessions.shared.index()
        for folder in folders.prefix(12) {
            // Only sessions that live in the Claude app: Pick up opens them there. Terminal and headless runs are skipped.
            let hit = folder.lazy.compactMap { item -> (item: (url: URL, mtime: Date), digest: SessionDigest)? in
                guard let d = self.cachedDigest(item.url, mtime: item.mtime, parse: TranscriptParser.digest), d.lastTimestamp != nil,
                      let id = d.sessionId, desktop[id] != nil, !Recap.isTrivial(d) else { return nil }
                return (item, d)
            }.first
            guard let hit, let cwd = hit.digest.cwd, !seen.contains(cwd), usable(cwd) else { continue }
            let item = hit.item
            var digest = hit.digest
            seen.insert(cwd)
            let app = digest.sessionId.flatMap { desktop[$0] }
            if let t = app?.title, !t.isEmpty { digest.title = t }      // the Claude app's own title wins
            let git = cachedGit(cwd).info
            if let p = Recap.project(digest: digest, git: git, now: now, desktopSessionId: app?.id, quietFor: now.timeIntervalSince(item.mtime)), let last = digest.lastTimestamp {
                out.append((p, digest, git, last))
            }
        }
        return out
    }

    // MARK: Codex (~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl)
    private func codexProjects() -> [Found] {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
        let cutoff = Date().addingTimeInterval(-Double(maxAgeDays) * 86_400)
        func sortedDesc(_ url: URL) -> [URL] {
            ((try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []).sorted { $0.lastPathComponent > $1.lastPathComponent }
        }
        var candidates: [(url: URL, mtime: Date)] = []
        outer: for year in sortedDesc(root) {
            for month in sortedDesc(year) {
                for day in sortedDesc(month) {
                    for file in sortedDesc(day) where file.pathExtension == "jsonl" {
                        guard let m = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { continue }
                        if m < cutoff { break outer }
                        candidates.append((file, m))
                    }
                    if candidates.count >= 40 { break outer }
                }
            }
        }
        candidates.sort { $0.mtime > $1.mtime }

        var seen = Set<String>(), out: [Found] = []
        let now = Date()
        for item in candidates.prefix(20) {
            guard var digest = cachedDigest(item.url, mtime: item.mtime, parse: CodexTranscript.digest) else { continue }
            if digest.cwd == nil || digest.sessionId == nil, let head = Self.head(of: item.url) { digest.cwd = digest.cwd ?? head.cwd; digest.sessionId = digest.sessionId ?? head.sessionId }
            guard let cwd = digest.cwd, !seen.contains(cwd), usable(cwd), !Recap.isTrivial(digest) else { continue }
            seen.insert(cwd)
            let cg = cachedGit(cwd, withBranch: true)
            let git = cg.info
            digest.branch = cg.branch
            if let p = Recap.project(digest: digest, git: git, now: now, desktopSessionId: nil, agent: "Codex", app: "codex", quietFor: now.timeIntervalSince(item.mtime)), let last = digest.lastTimestamp {
                out.append((p, digest, git, last))
            }
        }
        return out
    }

    /// The first line of a Codex file holds the folder and id, far from the tail we read for messages.
    static func head(of url: URL) -> SessionDigest? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 200_000), let text = String(data: data, encoding: .utf8),
              let first = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first else { return nil }
        return CodexTranscript.digest(lines: [String(first)])
    }

    /// Only the tail of the file: sessions can be tens of megabytes and the recent part is what matters.
    static func digest(of url: URL, parse: ([String]) -> SessionDigest) -> SessionDigest? {
        var result: SessionDigest?
        // Busy sessions can end in megabytes of tool output and images, so widen the window until real messages appear.
        for window in [600_000, 4_000_000, 16_000_000] as [UInt64] {
            guard let d = digest(of: url, tailBytes: window, parse: parse) else { continue }
            result = d
            if d.lastTimestamp != nil, d.lastUserText != nil { break }
        }
        return result
    }

    private static func digest(of url: URL, tailBytes: UInt64, parse: ([String]) -> SessionDigest) -> SessionDigest? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > tailBytes ? size - tailBytes : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(), var text = String(data: data, encoding: .utf8) else { return nil }
        if start > 0, let nl = text.firstIndex(of: "\n") { text = String(text[text.index(after: nl)...]) }   // drop the partial first line
        var d = parse(text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init))
        if d.title == nil, url.path.contains("/.claude/") { d.title = lastTitle(in: url) }
        return d
    }

    /// Session titles (custom-title records) are written occasionally, so they often sit outside the tail. Search the last 8 MB for the newest one.
    static func lastTitle(in url: URL, window: Int = 8_000_000) -> String? {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped), let marker = "\"type\":\"custom-title\"".data(using: .utf8) else { return nil }
        let lower = max(0, data.count - window)
        guard let hit = data.range(of: marker, options: .backwards, in: lower..<data.count) else { return nil }
        let start = (data[..<hit.lowerBound].lastIndex(of: 0x0A)).map { $0 + 1 } ?? 0
        let end = data[hit.upperBound...].firstIndex(of: 0x0A) ?? data.count
        guard let obj = (try? JSONSerialization.jsonObject(with: data[start..<end])) as? [String: Any] else { return nil }
        return obj["customTitle"] as? String
    }

    static func branch(at cwd: String) -> String? {
        let b = run("git", ["-C", cwd, "rev-parse", "--abbrev-ref", "HEAD"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (b?.isEmpty == false && b != "HEAD") ? b : nil
    }

    static func git(at cwd: String) -> GitInfo? {
        guard let status = run("git", ["-C", cwd, "status", "--porcelain", "-b"]) else { return nil }
        let last = run("git", ["-C", cwd, "log", "-1", "--format=%s"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        return GitInfo.parse(status: status, lastCommit: last)
    }

    private static func run(_ tool: String, _ args: [String]) -> String? {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/env"); p.arguments = [tool] + args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }
}

/// The Claude app keeps its own list of Code sessions. This maps a transcript id to the app's id and title.
final class DesktopSessions: @unchecked Sendable {
    struct Entry { let id: String; let title: String? }
    static let shared = DesktopSessions()
    /// Parsed files by path, read again only when they change. A busy session triggers a scan every half second.
    private var cache: [String: (mtime: Date, cli: String, entry: Entry)] = [:]
    private let lock = NSLock()

    /// Keys are the transcript ids (the app calls them cliSessionId).
    func index() -> [String: Entry] {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")
        let fm = FileManager.default
        lock.lock(); defer { lock.unlock() }
        var fresh: [String: (mtime: Date, cli: String, entry: Entry)] = [:]
        for account in (try? fm.contentsOfDirectory(atPath: root.path)) ?? [] {
            let accountDir = root.appendingPathComponent(account)
            for org in (try? fm.contentsOfDirectory(atPath: accountDir.path)) ?? [] {
                let dir = accountDir.appendingPathComponent(org)
                for file in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where file.hasPrefix("local_") && file.hasSuffix(".json") {
                    let url = dir.appendingPathComponent(file)
                    guard let mtime = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { continue }
                    if let hit = cache[url.path], hit.mtime == mtime { fresh[url.path] = hit; continue }
                    guard let data = try? Data(contentsOf: url),
                          let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                          let cli = o["cliSessionId"] as? String, let id = o["sessionId"] as? String else { continue }
                    fresh[url.path] = (mtime, cli, Entry(id: id, title: o["title"] as? String))
                }
            }
        }
        cache = fresh
        return Dictionary(fresh.values.map { ($0.cli, $0.entry) }, uniquingKeysWith: { a, _ in a })
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
            else { NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/Codex.app"), configuration: NSWorkspace.OpenConfiguration()); done(.app(codexApp, exact: false)) }
            return
        }
        if let id = p.desktopSessionId, let url = URL(string: "claude://code/continue?session=\(id)") {
            NSWorkspace.shared.open(url); done(.app(claudeApp, exact: true))
            return
        }
        done(.none)   // sample data does nothing
    }
}
