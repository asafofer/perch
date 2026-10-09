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
        let out = Array(all.filter { isEnabled($0.project.app) }.prefix(maxProjects))
        let fresh = Dictionary(out.map { ($0.project.id, (digest: $0.digest, git: $0.git)) }, uniquingKeysWith: { a, _ in a })
        lock.lock(); _inputs = fresh; lock.unlock()
        return out.map(\.project)
    }

    /// Reading a session tail is the slow part, so a file is only read again when it changed.
    private var digestCache: [String: (mtime: Date, digest: SessionDigest)] = [:]
    private var gitCache: [String: (at: Date, info: GitInfo?, branch: String?)] = [:]
    /// The first line of a Codex file never changes once written.
    private var headCache: [String: SessionDigest] = [:]
    private var threadNames: (mtime: Date, names: [String: String])?

    private func cachedDigest(_ url: URL, mtime: Date, parse: ([String]) -> SessionDigest) -> SessionDigest? {
        lock.lock(); let hit = digestCache[url.path]; lock.unlock()
        if let hit, hit.mtime == mtime { return hit.digest }
        guard let d = Self.digest(of: url, parse: parse) else { return nil }
        lock.lock(); digestCache[url.path] = (mtime, d); lock.unlock()
        return d
    }

    private func cachedHead(_ url: URL) -> SessionDigest? {
        lock.lock(); let hit = headCache[url.path]; lock.unlock()
        if let hit { return hit }
        guard let d = Self.head(of: url), d.sessionId != nil else { return nil }
        lock.lock(); headCache[url.path] = d; lock.unlock()
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
        !cwd.contains("/scratchpad") && !cwd.hasPrefix("/private/tmp") && !cwd.hasPrefix("/tmp") && !cwd.hasPrefix("/var/")
            && FileManager.default.fileExists(atPath: cwd)
    }

    private static func mtime(_ url: URL) -> Date? { try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }

    // MARK: Claude Code (~/.claude/projects/*/<id>.jsonl)
    /// The Claude app's own list decides: every session it shows, archived ones left out. A folder full of terminal
    /// or headless runs can no longer push an app session out of reach.
    private func claudeProjects() -> [Found] {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        let cutoff = Date().addingTimeInterval(-Double(maxAgeDays) * 86_400)
        // Claude Code names a session's folder after its path. Long or unusual paths are found by a full listing instead.
        var listing: [String: URL]?
        func transcript(_ cli: String, cwd: String?) -> URL? {
            if let cwd {
                let dir = String(cwd.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
                let url = root.appendingPathComponent(dir).appendingPathComponent(cli + ".jsonl")
                if fm.fileExists(atPath: url.path) { return url }
            }
            if listing == nil {
                var all: [String: URL] = [:]
                for dir in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
                    for f in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] where f.pathExtension == "jsonl" {
                        all[f.deletingPathExtension().lastPathComponent] = f
                    }
                }
                listing = all
            }
            return listing?[cli]
        }
        let sessions = DesktopSessions.shared.index()
            .filter { !$0.value.archived }
            .compactMap { cli, entry -> (entry: DesktopSessions.Entry, url: URL, mtime: Date)? in
                guard let url = transcript(cli, cwd: entry.cwd), let m = Self.mtime(url), m > cutoff else { return nil }
                return (entry, url, m)
            }
            .sorted { $0.mtime > $1.mtime }

        var out: [Found] = []
        let now = Date()
        for s in sessions {
            guard out.count < maxProjects else { break }
            guard var digest = cachedDigest(s.url, mtime: s.mtime, parse: TranscriptParser.digest), digest.lastTimestamp != nil,
                  !Recap.isTrivial(digest), let cwd = digest.cwd ?? s.entry.cwd, usable(cwd) else { continue }
            digest.cwd = cwd
            if let t = s.entry.title, !t.isEmpty { digest.title = t }      // the Claude app's own title wins
            let git = cachedGit(cwd).info
            if let p = Recap.project(digest: digest, git: git, now: now, desktopSessionId: s.entry.id, quietFor: now.timeIntervalSince(s.mtime)), let last = digest.lastTimestamp {
                out.append((p, digest, git, last))
            }
        }
        return out
    }

    // MARK: Codex (~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl)
    private func codexProjects() -> [Found] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        let cutoff = Date().addingTimeInterval(-Double(maxAgeDays) * 86_400)
        func entries(_ url: URL) -> [URL] { (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? [] }
        // A thread resumed today still lives in the folder of the day it began, so every file's age is checked.
        var candidates: [(url: URL, mtime: Date)] = []
        for year in entries(home.appendingPathComponent("sessions")) {
            for month in entries(year) {
                for day in entries(month) {
                    for file in entries(day) where file.pathExtension == "jsonl" {
                        if let m = Self.mtime(file), m > cutoff { candidates.append((file, m)) }
                    }
                }
            }
        }
        candidates.sort { $0.mtime > $1.mtime }
        let names = codexThreadNames(home.appendingPathComponent("session_index.jsonl"))

        var out: [Found] = []
        let now = Date()
        for item in candidates {
            guard out.count < maxProjects else { break }
            // Only threads you started: `codex exec` runs and subagents are not something to go back to.
            guard let head = cachedHead(item.url), !head.headless, let cwd = head.cwd, usable(cwd),
                  var digest = cachedDigest(item.url, mtime: item.mtime, parse: CodexTranscript.digest) else { continue }
            digest.cwd = cwd; digest.sessionId = head.sessionId
            guard !Recap.isTrivial(digest) else { continue }
            if let id = head.sessionId, let t = names[id], !t.isEmpty { digest.title = t }
            let cg = cachedGit(cwd, withBranch: true)
            let git = cg.info
            digest.branch = cg.branch
            if let p = Recap.project(digest: digest, git: git, now: now, desktopSessionId: nil, agent: "Codex", app: "codex", quietFor: now.timeIntervalSince(item.mtime)), let last = digest.lastTimestamp {
                out.append((p, digest, git, last))
            }
        }
        return out
    }

    /// The names Codex shows for its threads, newest last in the file.
    private func codexThreadNames(_ url: URL) -> [String: String] {
        guard let m = Self.mtime(url) else { return [:] }
        lock.lock(); let hit = threadNames; lock.unlock()
        if let hit, hit.mtime == m { return hit.names }
        var names: [String: String] = [:]
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            for line in text.split(separator: "\n") {
                guard let o = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                      let id = o["id"] as? String, let name = o["thread_name"] as? String else { continue }
                names[id] = name
            }
        }
        lock.lock(); threadNames = (m, names); lock.unlock()
        return names
    }

    /// The first line of a Codex file holds the folder and id, far from the tail we read for messages.
    static func head(of url: URL) -> SessionDigest? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        // Cut at the newline before decoding: a chunk that ends inside a character (Hebrew, emoji) is not valid UTF-8.
        guard let data = try? handle.read(upToCount: 1_000_000), let end = data.firstIndex(of: 0x0A),
              let first = String(data: data[data.startIndex..<end], encoding: .utf8) else { return nil }
        return CodexTranscript.digest(lines: [first])
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
        guard var data = try? handle.readToEnd() else { return nil }
        // Drop the partial first line before decoding: a tail that starts inside a character (Hebrew, emoji) is not valid UTF-8.
        if start > 0, let nl = data.firstIndex(of: 0x0A) { data = data[(nl + 1)...] }
        guard let text = String(data: data, encoding: .utf8) else { return nil }
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
    struct Entry { let id: String; let title: String?; let cwd: String?; let archived: Bool }
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
                    fresh[url.path] = (mtime, cli, Entry(id: id, title: o["title"] as? String, cwd: o["cwd"] as? String, archived: o["isArchived"] as? Bool ?? false))
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
