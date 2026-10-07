import Foundation

/// What we learn from the tail of one Claude Code session file.
public struct SessionDigest: Equatable, Sendable {
    public var sessionId: String?
    public var cwd: String?
    public var branch: String?
    public var title: String?
    public var lastUserText: String?
    public var lastAssistantText: String?
    public var lastTimestamp: Date?
    /// "user" or "assistant": who spoke last.
    public var lastRole: String?
    public init() {}
}

public enum TranscriptParser {
    /// Reads JSONL lines in file order and keeps the latest of each fact. Unknown or broken lines are skipped.
    public static func digest(lines: [String]) -> SessionDigest {
        var d = SessionDigest()
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
            let type = o["type"] as? String
            if type == "custom-title", let t = o["customTitle"] as? String, !t.isEmpty { d.title = t }
            else if type == "ai-title", let t = o["aiTitle"] as? String, !t.isEmpty, d.title == nil { d.title = t }
            if o["isSidechain"] as? Bool == true { continue }
            if let s = o["sessionId"] as? String { d.sessionId = s }
            if let c = o["cwd"] as? String { d.cwd = c }
            if let b = o["gitBranch"] as? String, !b.isEmpty, b != "HEAD" { d.branch = b }
            guard type == "user" || type == "assistant", o["isMeta"] as? Bool != true else { continue }
            guard let text = text(from: (o["message"] as? [String: Any])?["content"]), !text.isEmpty else { continue }
            if let ts = o["timestamp"] as? String, let date = iso.date(from: ts) ?? isoPlain.date(from: ts) { d.lastTimestamp = date }
            if type == "user" { d.lastUserText = text } else { d.lastAssistantText = text }
            d.lastRole = type
        }
        return d
    }

    /// Plain text of a message, without injected reminders or command wrappers. Tool results count as no text.
    static func text(from content: Any?) -> String? {
        var raw = ""
        if let s = content as? String { raw = s }
        else if let blocks = content as? [[String: Any]] {
            raw = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: " ")
        }
        raw = strip(raw, open: "<system-reminder>", close: "</system-reminder>")
        raw = strip(raw, open: "<command-name>", close: "</command-name>")
        raw = strip(raw, open: "<command-message>", close: "</command-message>")
        raw = strip(raw, open: "<command-args>", close: "</command-args>")
        raw = strip(raw, open: "<local-command-stdout>", close: "</local-command-stdout>")
        let t = raw.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("[Request interrupted") || t.hasPrefix("Caveat:") { return nil }
        return t.isEmpty ? nil : t
    }

    private static func strip(_ s: String, open: String, close: String) -> String {
        var out = s
        while let a = out.range(of: open), let b = out.range(of: close, range: a.upperBound..<out.endIndex) {
            out.removeSubrange(a.lowerBound..<b.upperBound)
        }
        return out
    }
}

public struct GitInfo: Equatable, Sendable {
    public var uncommitted: Int
    public var lastCommit: String?
    public init(uncommitted: Int, lastCommit: String? = nil) { self.uncommitted = uncommitted; self.lastCommit = lastCommit }
}

public enum Recap {
    /// A plain, honest recap built from the transcript and git alone. No model call.
    public static func project(digest d: SessionDigest, git: GitInfo?, now: Date, calendar: Calendar = .current) -> Project? {
        guard let cwd = d.cwd, let last = d.lastTimestamp else { return nil }
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        let headline = headlineText(d)
        let context = d.lastUserText.map { "You last asked: “\(clip($0, 90))”" } ?? "Your last session is ready to resume."
        let (status, next) = statusAndNext(d, git)
        let agents = [AgentStatus(kind: status.kind, text: status.text)]
        return Project(id: d.sessionId ?? cwd, name: name, branch: d.branch, away: RelativeTime.away(from: last, to: now),
                       at: RelativeTime.clock(last, now: now, calendar: calendar), headline: headline, context: context, next: next,
                       topic: clip(d.title ?? d.lastUserText ?? name, 28), app: "claude", agents: agents,
                       steps: [RestoreStep(icon: "term", text: "Opened Terminal in \(name)"),
                               RestoreStep(icon: "term", text: "Resumed your Claude Code session")],
                       sessionId: d.sessionId, cwd: cwd)
    }

    static func headlineText(_ d: SessionDigest) -> String {
        let base = d.title ?? d.lastUserText ?? "Your last session"
        let t = clip(base, 70)
        let cap = t.prefix(1).uppercased() + t.dropFirst()
        return cap.hasSuffix(".") || cap.hasSuffix("…") ? cap : cap + "."
    }

    static func statusAndNext(_ d: SessionDigest, _ git: GitInfo?) -> ((kind: AgentStatus.Kind, text: String), String) {
        if d.lastRole == "user" { return ((.needsYou, "Waiting on Claude Code"), "Check whether Claude Code finished") }
        if let a = d.lastAssistantText, a.trimmingCharacters(in: .whitespaces).hasSuffix("?") {
            return ((.needsYou, "Claude asked you something"), "Answer: “\(clip(lastSentence(a), 70))”")
        }
        if let g = git, g.uncommitted > 0 {
            return ((.done, "Claude Code replied"), "Review \(g.uncommitted) uncommitted file\(g.uncommitted == 1 ? "" : "s")")
        }
        return ((.done, "Claude Code replied"), "Continue from Claude's last reply")
    }

    static func lastSentence(_ s: String) -> String {
        let parts = s.split(whereSeparator: { ".!\n".contains($0) }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        // keep the question mark that split() removed from neither side
        return (parts.last ?? s).trimmingCharacters(in: CharacterSet(charactersIn: " ?")) + "?"
    }

    static func clip(_ s: String, _ n: Int) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count <= n ? t : String(t.prefix(n - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

public enum RelativeTime {
    public static func away(from: Date, to now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(from)))
        if s < 90 { return "1m" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86_400 { let h = s / 3600, m = (s % 3600) / 60; return h < 6 && m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        return "\(s / 86_400)d"
    }

    public static func clock(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let f = DateFormatter(); f.calendar = calendar; f.locale = Locale(identifier: "en_US")
        f.dateFormat = "h:mm a"
        let time = f.string(from: date)
        if calendar.isDate(date, inSameDayAs: now) { return time }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: y) { return "Yesterday \(time)" }
        if let week = calendar.date(byAdding: .day, value: -6, to: now), date > week { f.dateFormat = "EEE h:mm a"; return f.string(from: date) }
        f.dateFormat = "MMM d"; return f.string(from: date)
    }
}
