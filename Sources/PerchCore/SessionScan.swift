import Foundation

/// The Claude app keeps its own list of Code sessions. This maps a transcript id to the app's id, title and focus.
public final class DesktopSessions: @unchecked Sendable {
    public struct Entry: Sendable {
        public let id: String
        public let title: String?
        public let cwd: String?
        public let archived: Bool
        /// The last time the session was in front of you in the Claude app.
        public let focusedAt: Date?
    }
    public static let shared = DesktopSessions(root: FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions"))
    let root: URL
    /// Parsed files by path, read again only when they change. A busy session triggers a scan every half second.
    private var cache: [String: (mtime: Date, cli: String, entry: Entry)] = [:]
    private let lock = NSLock()

    public init(root: URL) { self.root = root }

    /// Keys are the transcript ids (the app calls them cliSessionId).
    public func index() -> [String: Entry] {
        let fm = FileManager.default
        lock.lock(); defer { lock.unlock() }
        var fresh: [String: (mtime: Date, cli: String, entry: Entry)] = [:]
        for account in (try? fm.contentsOfDirectory(atPath: root.path)) ?? [] {
            let accountDir = root.appendingPathComponent(account)
            for org in (try? fm.contentsOfDirectory(atPath: accountDir.path)) ?? [] {
                let dir = accountDir.appendingPathComponent(org)
                for file in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where file.hasPrefix("local_") && file.hasSuffix(".json") {
                    let url = dir.appendingPathComponent(file)
                    guard let mtime = SessionScanner.mtime(url) else { continue }
                    if let hit = cache[url.path], hit.mtime == mtime { fresh[url.path] = hit; continue }
                    guard let data = try? Data(contentsOf: url),
                          let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                          let cli = o["cliSessionId"] as? String, let id = o["sessionId"] as? String else { continue }
                    let focused = (o["lastFocusedAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
                    fresh[url.path] = (mtime, cli, Entry(id: id, title: o["title"] as? String, cwd: o["cwd"] as? String,
                                                         archived: o["isArchived"] as? Bool ?? false, focusedAt: focused))
                }
            }
        }
        cache = fresh
        return Dictionary(fresh.values.map { ($0.cli, $0.entry) }, uniquingKeysWith: { a, _ in a })
    }
}

/// Finds the sessions worth a row: every session the Claude app lists and every Codex thread you started, newest first.
public final class SessionScanner: @unchecked Sendable {
    public typealias Found = (project: Project, digest: SessionDigest, git: GitInfo?, last: Date)
    public var maxAgeDays = 14
    /// Whether a folder is somewhere you would go back to. Scratchpads and temporary folders are not.
    public var usable: (String) -> Bool = SessionScanner.isUsable
    public var lookUpGit: (String) -> GitInfo? = SessionScanner.git(at:)
    public var lookUpBranch: (String) -> String? = SessionScanner.branch(at:)
    /// For a git worktree, the name of the project it belongs to. Nil for anything else.
    public var lookUpRepo: (String) -> String? = SessionScanner.repo(at:)
    let home: URL
    let desktop: DesktopSessions

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, desktop: DesktopSessions = .shared) {
        self.home = home; self.desktop = desktop
    }

    /// Reading a session tail is the slow part, so a file is only read again when it changed.
    private var digestCache: [String: (mtime: Date, digest: SessionDigest)] = [:]
    private var gitCache: [String: (at: Date, info: GitInfo?, branch: String?)] = [:]
    /// Whether a folder is a worktree, and of which project, does not change.
    private var repoCache: [String: String?] = [:]
    private func cachedRepo(_ cwd: String) -> String? {
        lock.lock(); let hit = repoCache[cwd]; lock.unlock()
        if let hit { return hit }
        let r = lookUpRepo(cwd)
        lock.lock(); repoCache[cwd] = .some(r); lock.unlock()
        return r
    }
    /// The first line of a Codex file never changes once written.
    private var headCache: [String: SessionDigest] = [:]
    private var threadNames: (mtime: Date, names: [String: String])?
    private let lock = NSLock()

    public static func isUsable(_ cwd: String) -> Bool {
        !cwd.contains("/scratchpad") && !cwd.hasPrefix("/private/tmp") && !cwd.hasPrefix("/tmp") && !cwd.hasPrefix("/var/")
            && FileManager.default.fileExists(atPath: cwd)
    }

    static func mtime(_ url: URL) -> Date? { try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
    static func created(_ url: URL) -> Date? { try? url.resourceValues(forKeys: [.creationDateKey]).creationDate }

    private func cachedDigest(_ url: URL, mtime: Date, parse: ([String]) -> SessionDigest) -> SessionDigest? {
        lock.lock(); let hit = digestCache[url.path]; lock.unlock()
        if let hit, hit.mtime == mtime { return hit.digest }
        guard let d = Self.digest(of: url, parse: parse) else { return nil }
        lock.lock(); digestCache[url.path] = (mtime, d); lock.unlock()
        return d
    }

    private func cachedHead(_ url: URL, parse: ([String]) -> SessionDigest = CodexTranscript.digest) -> SessionDigest? {
        lock.lock(); let hit = headCache[url.path]; lock.unlock()
        if let hit { return hit }
        guard let d = Self.head(of: url, parse: parse), d.sessionId != nil else { return nil }
        lock.lock(); headCache[url.path] = d; lock.unlock()
        return d
    }

    /// Git state changes slowly next to a conversation, so it is looked up at most every 30 seconds per folder.
    private func cachedGit(_ cwd: String, withBranch: Bool = false) -> (info: GitInfo?, branch: String?) {
        lock.lock(); let hit = gitCache[cwd]; lock.unlock()
        if let hit, Date().timeIntervalSince(hit.at) < 30, !withBranch || hit.branch != nil { return (hit.info, hit.branch) }
        let info = lookUpGit(cwd), branch = withBranch ? lookUpBranch(cwd) : hit?.branch
        lock.lock(); gitCache[cwd] = (Date(), info, branch); lock.unlock()
        return (info, branch)
    }

    // MARK: Claude Code (~/.claude/projects/*/<id>.jsonl)
    /// The Claude app's own list decides: every session it shows, archived ones left out. A folder full of terminal
    /// or headless runs can never push an app session out of reach.
    public func claude(limit: Int, now: Date = Date()) -> [Found] {
        let fm = FileManager.default
        let root = home.appendingPathComponent(".claude/projects")
        let cutoff = now.addingTimeInterval(-Double(maxAgeDays) * 86_400)
        // Every transcript by id. Claude Code names a session's folder after its path, but long or unusual paths differ.
        var all: [String: URL] = [:]
        for dir in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            for f in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] where f.pathExtension == "jsonl" {
                all[f.deletingPathExtension().lastPathComponent] = f
            }
        }
        func transcript(_ cli: String, cwd: String?) -> URL? {
            if let cwd {
                let dir = String(cwd.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
                let url = root.appendingPathComponent(dir).appendingPathComponent(cli + ".jsonl")
                if fm.fileExists(atPath: url.path) { return url }
            }
            return all[cli]
        }
        let sessions = desktop.index()
            .filter { !$0.value.archived }
            .compactMap { cli, entry -> (entry: DesktopSessions.Entry, url: URL, mtime: Date)? in
                guard let url = transcript(cli, cwd: entry.cwd), let m = Self.mtime(url), m > cutoff else { return nil }
                return (entry, url, m)
            }
            .sorted { $0.mtime > $1.mtime }

        var out: [Found] = []
        // Sessions started in a terminal: the transcripts the app does not list, started from the command line.
        // Headless runs (`claude -p`, SDKs) and sessions the app has since deleted are not.
        let listed = Set(desktop.index().keys)
        let terminal = all.compactMap { cli, url -> (url: URL, mtime: Date)? in
            guard !listed.contains(cli), let m = Self.mtime(url), m > cutoff else { return nil }
            return (url, m)
        }.sorted { $0.mtime > $1.mtime }
        var fromTerminal = 0
        for t in terminal {
            guard fromTerminal < limit else { break }
            guard var digest = cachedDigest(t.url, mtime: t.mtime, parse: TranscriptParser.digest), digest.lastTimestamp != nil,
                  digest.entrypoint == nil || digest.entrypoint == "cli", !Recap.isTrivial(digest), let cwd = digest.cwd, usable(cwd) else { continue }
            digest.repoName = cachedRepo(cwd)
            let git = cachedGit(cwd).info
            if var p = Recap.project(digest: digest, git: git, now: now, quietFor: now.timeIntervalSince(t.mtime)), let last = digest.lastTimestamp {
                p.terminal = true; p.startedAt = Self.created(t.url)
                out.append((p, digest, git, last)); fromTerminal += 1
            }
        }
        for s in sessions {
            guard out.count < limit + fromTerminal else { break }
            guard var digest = cachedDigest(s.url, mtime: s.mtime, parse: TranscriptParser.digest), digest.lastTimestamp != nil,
                  // The app's folder for the session wins: the transcript's follows every `cd` the agent makes.
                  !Recap.isTrivial(digest), let cwd = s.entry.cwd ?? digest.cwd, usable(cwd) else { continue }
            digest.cwd = cwd
            if let t = s.entry.title, !t.isEmpty { digest.title = t }      // the Claude app's own title wins
            digest.repoName = cachedRepo(cwd)
            let git = cachedGit(cwd).info
            if var p = Recap.project(digest: digest, git: git, now: now, desktopSessionId: s.entry.id, quietFor: now.timeIntervalSince(s.mtime)), let last = digest.lastTimestamp {
                p.focusedAt = s.entry.focusedAt
                out.append((p, digest, git, last))
            }
        }
        return out
    }

    // MARK: Codex (~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl)
    public func codex(limit: Int, now: Date = Date()) -> [Found] {
        let fm = FileManager.default
        let root = home.appendingPathComponent(".codex")
        let cutoff = now.addingTimeInterval(-Double(maxAgeDays) * 86_400)
        func entries(_ url: URL) -> [URL] { (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? [] }
        // A thread resumed today still lives in the folder of the day it began, so every file's age is checked.
        var candidates: [(url: URL, mtime: Date)] = []
        for year in entries(root.appendingPathComponent("sessions")) {
            for month in entries(year) {
                for day in entries(month) {
                    for file in entries(day) where file.pathExtension == "jsonl" {
                        if let m = Self.mtime(file), m > cutoff { candidates.append((file, m)) }
                    }
                }
            }
        }
        candidates.sort { $0.mtime > $1.mtime }
        let names = codexThreadNames(root.appendingPathComponent("session_index.jsonl"))

        var out: [Found] = []
        for item in candidates {
            guard out.count < limit else { break }
            // Only threads you started: `codex exec` runs and subagents are not something to go back to.
            guard let head = cachedHead(item.url), !head.headless, let cwd = head.cwd, usable(cwd),
                  var digest = cachedDigest(item.url, mtime: item.mtime, parse: CodexTranscript.digest) else { continue }
            digest.cwd = cwd; digest.sessionId = head.sessionId
            guard !Recap.isTrivial(digest) else { continue }
            if let id = head.sessionId, let t = names[id], !t.isEmpty { digest.title = t }
            digest.repoName = cachedRepo(cwd)
            let cg = cachedGit(cwd, withBranch: true)
            let git = cg.info
            digest.branch = cg.branch
            if var p = Recap.project(digest: digest, git: git, now: now, desktopSessionId: nil, agent: .codex, quietFor: now.timeIntervalSince(item.mtime)), let last = digest.lastTimestamp {
                p.terminal = head.entrypoint == "cli"   // the Codex CLI in a terminal, not the Codex app
                p.startedAt = Self.created(item.url)
                out.append((p, digest, git, last))
            }
        }
        return out
    }

    // MARK: OpenCode (~/.local/share/opencode/opencode.db)
    /// Every session OpenCode lists (its subagents' and archived ones left out), terminal and desktop app alike.
    public func opencode(limit: Int, now: Date = Date()) -> [Found] {
        guard let store = OpenCodeStore(url: home.appendingPathComponent(".local/share/opencode/opencode.db")) else { return [] }
        let cutoff = now.addingTimeInterval(-Double(maxAgeDays) * 86_400)
        var out: [Found] = []
        for s in store.sessions(after: cutoff, limit: limit * 3) {
            guard out.count < limit else { break }
            guard usable(s.directory) else { continue }
            // Read again only when the session changed.
            let key = "opencode:" + s.id
            lock.lock(); let hit = digestCache[key]; lock.unlock()
            var digest: SessionDigest
            if let hit, hit.mtime == s.updated { digest = hit.digest }
            else { digest = OpenCodeTranscript.digest(store.messages(session: s.id)); lock.lock(); digestCache[key] = (s.updated, digest); lock.unlock() }
            guard digest.lastTimestamp != nil, !Recap.isTrivial(digest) else { continue }
            digest.sessionId = s.id; digest.cwd = s.directory
            if !OpenCodeTranscript.isPlaceholder(s.title) { digest.title = s.title }
            digest.repoName = cachedRepo(s.directory)
            let cg = cachedGit(s.directory, withBranch: true)
            digest.branch = cg.branch
            if var p = Recap.project(digest: digest, git: cg.info, now: now, agent: .opencode, quietFor: now.timeIntervalSince(s.updated)), let last = digest.lastTimestamp {
                p.terminal = true; p.startedAt = s.created
                out.append((p, digest, cg.info, last))
            }
        }
        return out
    }

    // MARK: pi (~/.pi/agent/sessions/--<folder>--/<time>_<id>.jsonl)
    public func pi(limit: Int, now: Date = Date()) -> [Found] {
        let fm = FileManager.default
        let root = home.appendingPathComponent(".pi/agent/sessions")
        let cutoff = now.addingTimeInterval(-Double(maxAgeDays) * 86_400)
        var candidates: [(url: URL, mtime: Date)] = []
        for dir in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            for f in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] where f.pathExtension == "jsonl" {
                if let m = Self.mtime(f), m > cutoff { candidates.append((f, m)) }
            }
        }
        candidates.sort { $0.mtime > $1.mtime }
        var out: [Found] = []
        for item in candidates {
            guard out.count < limit else { break }
            guard let head = cachedHead(item.url, parse: PiTranscript.digest), let cwd = head.cwd, usable(cwd),
                  var digest = cachedDigest(item.url, mtime: item.mtime, parse: PiTranscript.digest) else { continue }
            digest.cwd = cwd; digest.sessionId = head.sessionId
            guard digest.lastTimestamp != nil, !Recap.isTrivial(digest) else { continue }
            // Unnamed, it goes by your first prompt, as pi's own list does.
            if digest.title == nil { digest.title = cachedFirstPrompt(item.url) }
            digest.repoName = cachedRepo(cwd)
            let cg = cachedGit(cwd, withBranch: true)
            digest.branch = cg.branch
            if var p = Recap.project(digest: digest, git: cg.info, now: now, agent: .pi, quietFor: now.timeIntervalSince(item.mtime)), let last = digest.lastTimestamp {
                p.terminal = true; p.startedAt = Self.created(item.url)
                out.append((p, digest, cg.info, last))
            }
        }
        return out
    }

    private var firstPrompts: [String: String] = [:]
    private func cachedFirstPrompt(_ url: URL) -> String? {
        lock.lock(); let hit = firstPrompts[url.path]; lock.unlock()
        if let hit { return hit }
        guard let t = PiTranscript.firstPrompt(in: url) else { return nil }
        lock.lock(); firstPrompts[url.path] = t; lock.unlock()
        return t
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

    /// The first line of a Codex or pi file holds the folder and id, far from the tail we read for messages.
    static func head(of url: URL, parse: ([String]) -> SessionDigest = CodexTranscript.digest) -> SessionDigest? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        // Cut at the newline before decoding: a chunk that ends inside a character (Hebrew, emoji) is not valid UTF-8.
        guard let data = try? handle.read(upToCount: 1_000_000), let end = data.firstIndex(of: 0x0A),
              let first = String(data: data[data.startIndex..<end], encoding: .utf8) else { return nil }
        return parse([first])
    }

    /// Only the tail of the file: sessions can be tens of megabytes and the recent part is what matters.
    /// Busy sessions can end in megabytes of tool output and images, so the window widens until real messages appear.
    static func digest(of url: URL, windows: [UInt64] = [600_000, 4_000_000, 16_000_000], parse: ([String]) -> SessionDigest) -> SessionDigest? {
        var result: SessionDigest?
        for window in windows {
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
        if d.title == nil, url.path.contains("/.pi/") { d.title = lastTitle(in: url, marker: #""type":"session_info""#, key: "name") }
        return d
    }

    /// Session titles (Claude's custom-title records, pi's session_info) are written occasionally, so they often sit
    /// outside the tail. Search the last 8 MB for the newest one.
    static func lastTitle(in url: URL, window: Int = 8_000_000, marker text: String = #""type":"custom-title""#, key: String = "customTitle") -> String? {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped), let marker = text.data(using: .utf8) else { return nil }
        let lower = max(0, data.count - window)
        guard let hit = data.range(of: marker, options: .backwards, in: lower..<data.count) else { return nil }
        let start = (data[..<hit.lowerBound].lastIndex(of: 0x0A)).map { $0 + 1 } ?? 0
        let end = data[hit.upperBound...].firstIndex(of: 0x0A) ?? data.count
        guard let obj = (try? JSONSerialization.jsonObject(with: data[start..<end])) as? [String: Any] else { return nil }
        return (obj[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// A linked git worktree keeps its git folder inside the main checkout's (`git-common-dir`), whose folder names the project.
    public static func repo(at cwd: String) -> String? {
        guard let out = run("git", ["-C", cwd, "rev-parse", "--path-format=absolute", "--git-common-dir", "--git-dir"]) else { return nil }
        let lines = out.split(separator: "\n").map(String.init)
        guard lines.count == 2, lines[0] != lines[1], (lines[0] as NSString).lastPathComponent == ".git" else { return nil }
        return ((lines[0] as NSString).deletingLastPathComponent as NSString).lastPathComponent
    }

    public static func branch(at cwd: String) -> String? {
        let b = run("git", ["-C", cwd, "rev-parse", "--abbrev-ref", "HEAD"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (b?.isEmpty == false && b != "HEAD") ? b : nil
    }

    public static func git(at cwd: String) -> GitInfo? {
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
