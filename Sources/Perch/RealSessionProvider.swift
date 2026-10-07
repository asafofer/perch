import Foundation
import PerchCore

/// Reads the newest session of each recent project from ~/.claude/projects and turns it into a card.
struct RealSessionProvider: SessionProviding {
    var maxProjects = 5
    var maxAgeDays = 14

    func parkedProjects() -> [Project] {
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

        var seen = Set<String>(), out: [Project] = []
        let now = Date()
        for item in newest {
            guard let digest = Self.digest(of: item.url), let cwd = digest.cwd, !seen.contains(cwd),
                  !cwd.contains("/scratch-workspaces/"), !cwd.contains("/scratchpad"),
                  !cwd.hasPrefix("/private/tmp"), !cwd.hasPrefix("/tmp"), !cwd.hasPrefix("/var/"),
                  FileManager.default.fileExists(atPath: cwd) else { continue }
            seen.insert(cwd)
            if let p = Recap.project(digest: digest, git: Self.git(at: cwd), now: now) { out.append(p) }
            if out.count == maxProjects { break }
        }
        return out
    }

    /// Only the tail of the file: sessions can be tens of megabytes and the recent part is what matters.
    static func digest(of url: URL) -> SessionDigest? {
        var result: SessionDigest?
        // Busy sessions can end in megabytes of tool output and images, so widen the window until real messages appear.
        for window in [600_000, 4_000_000, 16_000_000] as [UInt64] {
            guard let d = digest(of: url, tailBytes: window) else { continue }
            result = d
            if d.cwd != nil, d.lastTimestamp != nil, d.lastUserText != nil { break }
        }
        return result
    }

    private static func digest(of url: URL, tailBytes: UInt64) -> SessionDigest? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > tailBytes ? size - tailBytes : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(), var text = String(data: data, encoding: .utf8) else { return nil }
        if start > 0, let nl = text.firstIndex(of: "\n") { text = String(text[text.index(after: nl)...]) }   // drop the partial first line
        var d = TranscriptParser.digest(lines: text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init))
        if d.title == nil { d.title = lastTitle(in: url) }
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

    static func git(at cwd: String) -> GitInfo? {
        guard let status = run("git", ["-C", cwd, "status", "--porcelain"]) else { return nil }
        let n = status.split(separator: "\n").count
        return GitInfo(uncommitted: n, lastCommit: run("git", ["-C", cwd, "log", "-1", "--format=%s"])?.trimmingCharacters(in: .whitespacesAndNewlines))
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

/// What "Pick up" does for a real session: open Terminal in the project and resume the Claude Code session.
enum Restorer {
    static func resume(_ p: Project) {
        guard let cwd = p.cwd, let id = p.sessionId else { return }   // sample data does nothing
        let command = "cd \(shellQuote(cwd)) && claude --resume \(id)"
        let script = "tell application \"Terminal\"\nactivate\ndo script \"\(command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\"\nend tell"
        let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript"); task.arguments = ["-e", script]
        task.standardError = Pipe()
        do { try task.run() } catch { NSLog("Perch: could not open Terminal: \(error)") }
    }
    private static func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
