import AppKit
import PerchCore

/// Reads the newest session of each recent project from ~/.claude/projects and turns it into a card.
final class RealSessionProvider: SessionProviding, @unchecked Sendable {
    var maxProjects = 5
    var maxAgeDays = 14
    /// What the last scan read, so a model can write about it without reading the files again.
    private var _inputs: [String: (digest: SessionDigest, git: GitInfo?)] = [:]
    private let lock = NSLock()
    var inputs: [String: (digest: SessionDigest, git: GitInfo?)] { lock.lock(); defer { lock.unlock() }; return _inputs }

    func parkedProjects() -> [Project] {
        var all = claudeProjects() + codexProjects()
        all.sort { $0.last > $1.last }
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

    typealias Found = (project: Project, digest: SessionDigest, git: GitInfo?, last: Date)

    private func usable(_ cwd: String) -> Bool {
        !cwd.contains("/scratch-workspaces/") && !cwd.contains("/scratchpad") && !cwd.hasPrefix("/private/tmp")
            && !cwd.hasPrefix("/tmp") && !cwd.hasPrefix("/var/") && FileManager.default.fileExists(atPath: cwd)
    }

    // MARK: Claude Code (~/.claude/projects/*/*.jsonl)
    /// A session file written to in the last 45 seconds means the agent is working right now.
    static let runningWindow: TimeInterval = 45

    private func claudeProjects() -> [Found] {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        guard let dirs = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        let cutoff = Date().addingTimeInterval(-Double(maxAgeDays) * 86_400)
        var newest: [(url: URL, mtime: Date)] = []
        for dir in dirs {
            guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            let best = files.filter { $0.pathExtension == "jsonl" }
                .compactMap { u -> (URL, Date)? in (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate).map { (u, $0) } }
                .max { $0.1 < $1.1 }
            if let best, best.1 > cutoff { newest.append((best.0, best.1)) }
        }
        newest.sort { $0.mtime > $1.mtime }

        var seen = Set<String>(), out: [Found] = []
        let now = Date()
        let desktop = DesktopSessions.index()
        for item in newest.prefix(12) {
            guard var digest = Self.digest(of: item.url, parse: TranscriptParser.digest), let cwd = digest.cwd, !seen.contains(cwd), usable(cwd) else { continue }
            seen.insert(cwd)
            let app = digest.sessionId.flatMap { desktop[$0] }
            if let t = app?.title, !t.isEmpty { digest.title = t }      // the Claude app's own title wins
            let git = Self.git(at: cwd)
            if let p = Recap.project(digest: digest, git: git, now: now, desktopSessionId: app?.id, running: now.timeIntervalSince(item.mtime) < Self.runningWindow), let last = digest.lastTimestamp {
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
            guard var digest = Self.digest(of: item.url, parse: CodexTranscript.digest) else { continue }
            if digest.cwd == nil || digest.sessionId == nil, let head = Self.head(of: item.url) { digest.cwd = digest.cwd ?? head.cwd; digest.sessionId = digest.sessionId ?? head.sessionId }
            guard let cwd = digest.cwd, !seen.contains(cwd), usable(cwd) else { continue }
            seen.insert(cwd)
            let git = Self.git(at: cwd)
            digest.branch = Self.branch(at: cwd)
            if let p = Recap.project(digest: digest, git: git, now: now, desktopSessionId: nil, agent: "Codex", app: "codex", running: now.timeIntervalSince(item.mtime) < Self.runningWindow), let last = digest.lastTimestamp {
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
enum DesktopSessions {
    struct Entry { let id: String; let title: String? }

    /// Keys are the transcript ids (the app calls them cliSessionId).
    static func index() -> [String: Entry] {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")
        var out: [String: Entry] = [:]
        let fm = FileManager.default
        for account in (try? fm.contentsOfDirectory(atPath: root.path)) ?? [] {
            let accountDir = root.appendingPathComponent(account)
            for org in (try? fm.contentsOfDirectory(atPath: accountDir.path)) ?? [] {
                let dir = accountDir.appendingPathComponent(org)
                for file in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where file.hasPrefix("local_") && file.hasSuffix(".json") {
                    guard let data = try? Data(contentsOf: dir.appendingPathComponent(file)),
                          let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                          let cli = o["cliSessionId"] as? String, let id = o["sessionId"] as? String else { continue }
                    out[cli] = Entry(id: id, title: o["title"] as? String)
                }
            }
        }
        return out
    }
}

/// What "Pick up" does for a real session: reopen it where you were working.
/// Sessions from the Claude app open in the Claude app; terminal sessions resume in Terminal.
enum Restorer {
    static func resume(_ p: Project) {
        // Codex: bring the Codex app forward. (Opening one exact thread needs a link Codex doesn't document.)
        if p.app == "codex" {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/Codex.app"), configuration: NSWorkspace.OpenConfiguration())
            return
        }
        if let id = p.desktopSessionId, let url = URL(string: "claude://code/continue?session=\(id)") {
            NSWorkspace.shared.open(url)
            return
        }
        guard let cwd = p.cwd, let id = p.sessionId else { return }   // sample data does nothing
        let command = "cd \(shellQuote(cwd)) && claude --resume \(id)"
        let script = "tell application \"Terminal\"\nactivate\ndo script \"\(command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\"\nend tell"
        let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript"); task.arguments = ["-e", script]
        task.standardError = Pipe()
        do { try task.run() } catch { NSLog("Perch: could not open Terminal: \(error)") }
    }
    private static func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
