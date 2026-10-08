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
    /// The agent's turn has started and not finished: its last record is a tool call, a tool result or your prompt.
    public var turnOpen = false
    /// The newest tool call that has no result yet, while the turn is open. A stale one usually means a permission prompt.
    public var pendingTool: PendingTool?
    /// You stopped the agent (Esc, or Codex's turn was aborted) and have not written since.
    public var interrupted = false
    /// The last thing you asked that says something: "yes", "ok go ahead" and "push it" are skipped.
    public var lastAsk: String?
    /// How the session was started: "cli", "claude-desktop", or "sdk-…" for headless runs like `claude -p`.
    public var entrypoint: String?
    /// The last dozen real messages, oldest first, each clipped. This is what a model reads.
    public var recent: [Line] = []
    public struct Line: Equatable, Sendable { public let role: String; public let text: String }
    public init() {}
}

public struct PendingTool: Equatable, Sendable {
    public let name: String
    /// The question, when the tool asks you one (AskUserQuestion).
    public let question: String?
    /// A Bash call's own timeout, so a long build is not mistaken for a wait.
    public let timeout: TimeInterval?
    public init(name: String, question: String? = nil, timeout: TimeInterval? = nil) { self.name = name; self.question = question; self.timeout = timeout }

    init(block b: [String: Any]) {
        let input = b["input"] as? [String: Any]
        let qs = input?["questions"] as? [[String: Any]]
        self.init(name: b["name"] as? String ?? "tool",
                  question: (qs?.first?["question"] as? String) ?? (input?["question"] as? String),
                  timeout: (input?["timeout"] as? Double).map { $0 / 1000 })
    }
}

public enum TranscriptParser {
    /// Reads JSONL lines in file order and keeps the latest of each fact. Unknown or broken lines are skipped.
    public static func digest(lines: [String]) -> SessionDigest {
        var d = SessionDigest()
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        var open: [(id: String, tool: PendingTool)] = []
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
            if let e = o["entrypoint"] as? String { d.entrypoint = e }
            guard type == "user" || type == "assistant", o["isMeta"] as? Bool != true else { continue }
            let message = o["message"] as? [String: Any]
            let blocks = message?["content"] as? [[String: Any]] ?? []
            if type == "assistant" {
                let done: Set<String> = ["end_turn", "stop_sequence", "max_tokens", "refusal"]
                d.turnOpen = !done.contains(message?["stop_reason"] as? String ?? "")
                for b in blocks where b["type"] as? String == "tool_use" { open.append((b["id"] as? String ?? "", PendingTool(block: b))) }
            } else if isInterrupt(message?["content"]) {
                d.turnOpen = false; d.interrupted = true; open = []
            } else {
                d.turnOpen = true
                let answered = Set(blocks.compactMap { $0["type"] as? String == "tool_result" ? $0["tool_use_id"] as? String : nil })
                open.removeAll { answered.contains($0.id) }
            }
            if !d.turnOpen { open = [] }
            guard let text = text(from: message?["content"]), !text.isEmpty else { continue }
            if let ts = o["timestamp"] as? String, let date = iso.date(from: ts) ?? isoPlain.date(from: ts) { d.lastTimestamp = date }
            if type == "user" { d.lastUserText = text; if !Recap.isAcknowledgement(text) { d.lastAsk = text } } else { d.lastAssistantText = text }
            d.interrupted = false
            d.lastRole = type
            d.recent.append(.init(role: type ?? "user", text: Recap.clip(text, 420)))
            if d.recent.count > 12 { d.recent.removeFirst() }
        }
        d.pendingTool = d.turnOpen ? open.last?.tool : nil
        return d
    }

    static func isInterrupt(_ content: Any?) -> Bool {
        if let s = content as? String { return s.hasPrefix("[Request interrupted") }
        if let blocks = content as? [[String: Any]] { return blocks.contains { ($0["text"] as? String)?.hasPrefix("[Request interrupted") == true } }
        return false
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
        raw = strip(raw, open: "<bash-stdout>", close: "</bash-stdout>")
        raw = strip(raw, open: "<bash-stderr>", close: "</bash-stderr>")
        raw = strip(raw, open: "<bash-input>", close: "</bash-input>")
        let t = raw.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("[Request interrupted") || t.hasPrefix("Caveat:") { return nil }
        if isMachineMessage(t) { return nil }
        return t.isEmpty ? nil : t
    }

    /// Harness-injected messages that arrive as "user" turns, like <task-notification>...</task-notification>.
    static func isMachineMessage(_ t: String) -> Bool {
        guard t.hasPrefix("<"), let close = t.firstIndex(of: ">") else { return false }
        let name = t[t.index(after: t.startIndex)..<close].split(separator: " ").first.map(String.init) ?? ""
        return !name.isEmpty && name.allSatisfy { $0.isLetter || $0 == "-" || $0 == "_" } && t.hasSuffix("</\(name)>")
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
    /// File names (not paths) of the uncommitted changes, most relevant first.
    public var files: [String]
    /// Commits not yet pushed to the upstream branch.
    public var ahead: Int
    public var branch: String?
    public init(uncommitted: Int, lastCommit: String? = nil, files: [String] = [], ahead: Int = 0, branch: String? = nil) {
        self.uncommitted = uncommitted; self.lastCommit = lastCommit; self.files = files; self.ahead = ahead; self.branch = branch
    }

    /// Parses `git status --porcelain -b` output.
    public static func parse(status: String, lastCommit: String?) -> GitInfo {
        var files: [String] = [], ahead = 0, branch: String?
        for line in status.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("## ") {
                let head = line.dropFirst(3)
                branch = String(head).components(separatedBy: "...").first
                if let r = head.range(of: "ahead "), let n = Int(String(head[r.upperBound...].prefix(while: { $0.isNumber }))) { ahead = n }
                continue
            }
            var path = String(line.dropFirst(3))
            if let arrow = path.range(of: " -> ") { path = String(path[arrow.upperBound...]) }
            path = path.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let name = (path as NSString).lastPathComponent
            if !name.isEmpty { files.append(name) }
        }
        var seen = Set<String>(); files = files.filter { seen.insert($0).inserted }
        return GitInfo(uncommitted: files.count, lastCommit: lastCommit, files: files, ahead: ahead, branch: branch)
    }
}

public enum Recap {
    /// A plain, honest recap built from the transcript and git alone. No model call.
    public static func project(digest d: SessionDigest, git: GitInfo?, now: Date, calendar: Calendar = .current, desktopSessionId: String? = nil, agent: String = "Claude Code", app: String = "claude", quietFor: TimeInterval? = nil) -> Project? {
        guard let cwd = d.cwd, let last = d.lastTimestamp else { return nil }
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        let headline = headlineText(d)
        let context = (d.lastAsk ?? d.lastUserText).map { "You last asked: “\(clip($0, 140))”" } ?? "Your last session is ready to resume."
        let (status, next) = statusAndNext(d, git, agent: agent, quietFor: quietFor)
        let agents = [AgentStatus(kind: status.kind, text: status.text, app: app)]
        var p = Project(id: d.sessionId ?? cwd, name: name, branch: d.branch, away: RelativeTime.away(from: last, to: now),
                       at: RelativeTime.clock(last, now: now, calendar: calendar), headline: headline, context: context, next: next,
                       topic: clip(d.title ?? d.lastAsk ?? d.lastUserText ?? name, 28), app: app, agents: agents,
                       steps: desktopSessionId != nil
                           ? [RestoreStep(icon: "win", text: "Opened the \(app == "codex" ? "Codex" : "Claude") app"), RestoreStep(icon: "term", text: "Went back to your session")]
                           : [RestoreStep(icon: "term", text: "Opened Terminal in \(name)"), RestoreStep(icon: "term", text: "Resumed your \(agent) session")],
                       sessionId: d.sessionId, cwd: cwd, desktopSessionId: desktopSessionId)
        p.lastActive = last
        return p
    }

    static func headlineText(_ d: SessionDigest) -> String {
        let base = d.title ?? d.lastAsk ?? d.lastUserText ?? "Your last session"
        let t = clip(base, 70)
        let cap = t.prefix(1).uppercased() + t.dropFirst()
        return cap.hasSuffix(".") || cap.hasSuffix("…") ? cap : cap + "."
    }

    /// A session counts as working while its turn is open and the file changed this recently.
    public static let runningWindow: TimeInterval = 150

    /// `quietFor` is how long ago the session file last changed; nil when unknown.
    static func statusAndNext(_ d: SessionDigest, _ git: GitInfo?, agent: String = "Claude Code", quietFor: TimeInterval? = nil) -> ((kind: AgentStatus.Kind, text: String), String) {
        let short = agent == "Codex" ? "Codex" : "Claude", quiet = quietFor ?? .infinity
        let working = ((AgentStatus.Kind.running, "\(agent) is working"), "")
        if d.turnOpen, let t = d.pendingTool {
            // Tools that wait on you by design.
            if t.name == "AskUserQuestion" {
                return ((.needsYou, "\(short) asked you something"), t.question.map { "Answer: “\(clip($0, 100))”" } ?? "")
            }
            if t.name == "ExitPlanMode" { return ((.needsYou, "\(short) has a plan for you"), "Review the plan") }
            // Any other call with no result: running for as long as it plausibly could, then it is waiting for your OK.
            let expected: TimeInterval = t.name == "Bash" ? (t.timeout ?? 120) + 15 : (["Task", "Agent"].contains(t.name) ? 1800 : 30)
            if quiet < expected { return working }
            if quiet < 4 * 3600 { return ((.needsYou, "\(short) is waiting for your OK"), "") }
            return ((.idle, "\(agent) stopped mid-task"), "")
        }
        if d.turnOpen && quiet < runningWindow { return working }
        if d.interrupted { return ((.idle, "You stopped \(short)"), "") }
        if d.lastRole == "user" { return ((.idle, "\(agent) stopped before replying"), "") }
        if let a = d.lastAssistantText, a.trimmingCharacters(in: .whitespaces).hasSuffix("?") {
            return ((.needsYou, "\(short) asked you something"), "Answer: “\(clip(lastSentence(a), 100))”")
        }
        let done = (kind: AgentStatus.Kind.done, text: "\(agent) replied")
        // Only a step the agent stated itself. Git housekeeping (committing, pushing) is never offered, and with
        // nothing real to suggest the card shows no next step at all.
        if let a = d.lastAssistantText, let step = explicitNext(in: a), !isGitChore(step) { return (done, clip(step, 100)) }   // the card labels it "Next" itself
        return (done, "")
    }

    /// Committing, pushing and merging are never useful as a suggested next step.
    /// Matches the chore, not the word: "Push the branch" is one, "Add push notifications" is not.
    public static func isGitChore(_ text: String) -> Bool {
        text.range(of: #"^\W*(commit|push|merge|rebase|stage)\b(?! notification)|\b(pull request|uncommitted|git (add|commit|push|merge|rebase))\b|\bopen (a|the) pr\b"#,
                   options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static let ackWords: Set<String> = ["yes", "yep", "yeah", "yup", "y", "ok", "okay", "k", "kk", "sure", "go", "ahead", "do", "it",
        "continue", "proceed", "thanks", "thank", "you", "ty", "lgtm", "perfect", "great", "nice", "cool", "good", "fine", "looks", "sounds",
        "push", "commit", "and", "merge", "ship", "please", "no", "nope", "that", "this", "now", "all", "right", "alright",
        "\u{05DB}\u{05DF}", "\u{05E1}\u{05D1}\u{05D1}\u{05D4}", "\u{05D0}\u{05D5}\u{05E7}\u{05D9}\u{05D9}", "\u{05EA}\u{05D5}\u{05D3}\u{05D4}"]

    /// A reply that only says go on ("yes", "ok go ahead", "push it please"). It tells you nothing about the work.
    public static func isAcknowledgement(_ text: String) -> Bool {
        let words = text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
        return !words.isEmpty && words.count <= 4 && words.allSatisfy { ackWords.contains($0) }
    }

    /// A next step the assistant stated itself: a line or sentence like "Next: …", "Then …", "Still to do: …".
    static func explicitNext(in text: String) -> String? {
        let cues = ["next:", "next,", "next I", "then ", "still to do", "remaining:", "to do:", "todo:", "left to do", "next step"]
        let pieces = text.replacingOccurrences(of: "\n", with: ". ").components(separatedBy: CharacterSet(charactersIn: ".!"))
        for raw in pieces.reversed() {
            var t = raw.trimmingCharacters(in: CharacterSet(charactersIn: " -•*\t"))
            guard t.count > 8 else { continue }
            let lower = t.lowercased()
            guard let cue = cues.first(where: { lower.hasPrefix($0.lowercased()) }) else { continue }
            t = String(t.dropFirst(cue.count)).trimmingCharacters(in: CharacterSet(charactersIn: " :,-"))
            if t.count > 6 { return t.prefix(1).uppercased() + t.dropFirst() }
        }
        return nil
    }

    static func lastSentence(_ s: String) -> String {
        let parts = s.split(whereSeparator: { ".!\n".contains($0) }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        // keep the question mark that split() removed from neither side
        return (parts.last ?? s).trimmingCharacters(in: CharacterSet(charactersIn: " ?")) + "?"
    }

    static func firstSentence(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if let end = t.firstIndex(where: { ".!?".contains($0) }) { return String(t[...end]).trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
        return t
    }

    public static func clip(_ s: String, _ n: Int) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > n else { return t }
        var cut = String(t.prefix(n - 1))
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > n * 6 / 10 { cut = String(cut[..<space]) }
        return cut.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-")) + "…"
    }
}

/// The line above the headline: what happened, measured against when you left rather than a bare age.
public enum WhileAway {
    /// `kind` is the card status ("attention", "done", "running", "idle"). `fresh`: you have not seen this since it changed.
    public static func line(kind: String, lastActive: Date?, now: Date, awaySince: Date?, fresh: Bool) -> String {
        guard let t = lastActive else { return "" }
        let ago = RelativeTime.away(from: t, to: now), recent = now.timeIntervalSince(t) < 90
        if kind == "running" { return "Working now" }
        if let left = awaySince, t > left {
            let after = t.timeIntervalSince(left) < 90 ? "just after you left" : "\(RelativeTime.away(from: left, to: t)) after you left"
            switch kind {
            case "attention": return "Waiting on you for \(ago)"
            case "done": return "Finished \(after)"
            default: return "Stopped \(after)"
            }
        }
        if kind == "attention" { return "Waiting on you for \(ago)" }
        if kind == "done" && fresh { return recent ? "Finished just now" : "Finished \(ago) ago" }
        return recent ? "Active just now" : "Last active \(ago) ago"
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

/// Words a model writes for the card. Only the three fields the UI shows.
public struct RecapText: Equatable, Codable, Sendable {
    public var headline: String
    public var context: String
    public var next: String
    public init(headline: String, context: String, next: String) { self.headline = headline; self.context = context; self.next = next }
}

public enum RecapPrompt {
    public static let instructions = """
    You write the welcome-back card for a developer returning to a coding session. \
    Use ONLY facts stated in the conversation or the git facts below. Never invent topics, files, bugs or tasks.
    - headline: what they were doing at the END of the conversation, about the latest messages and not older topics. \
    Second person, past tense, starting with "You were". Max 60 characters, ends with a period.
    - context: the key decision or where things stand now, in plain words. Max 110 characters.
    - next: the single most useful next step, as a short imperative. Base it on the LATEST messages and the git facts. \
    Never suggest something already done or merged, never suggest committing, pushing or merging, and never repeat a suggestion the user rejected. Max 60 characters.
    No markdown, no emoji, no quotation marks around the fields.
    """

    public static func build(digest d: SessionDigest, git: GitInfo?, projectName: String, agent: String = "Claude") -> String {
        var out = "Project: \(projectName)\n"
        if let t = d.title, !t.isEmpty { out += "Session title: \(t)\n" }
        if let g = git {
            out += "Git: \(g.uncommitted) uncommitted file\(g.uncommitted == 1 ? "" : "s")"
            if let c = g.lastCommit, !c.isEmpty { out += "; last commit: \(Recap.clip(c, 80))" }
            out += "\n"
        }
        let line: (SessionDigest.Line, Int) -> String = { ($0.role == "user" ? "User: " : "\(agent): ") + Recap.clip($0.text, $1) }
        let recent = Array(d.recent.suffix(8))
        let latest = recent.suffix(3), earlier = recent.dropLast(latest.count)
        if !earlier.isEmpty { out += "Earlier, background only (may be finished):\n" + earlier.map { line($0, 140) }.joined(separator: "\n") + "\n" }
        out += "Latest messages, oldest first (the card is about THESE):\n" + latest.map { line($0, 320) }.joined(separator: "\n")
        return out
    }

    /// Pulls the JSON object out of a model reply, tolerating code fences and chatter around it.
    public static func parse(_ raw: String) -> RecapText? {
        guard let a = raw.firstIndex(of: "{"), let b = raw.lastIndex(of: "}"), a < b,
              let data = String(raw[a...b]).data(using: .utf8),
              var t = try? JSONDecoder().decode(RecapText.self, from: data) else { return nil }
        t.headline = Recap.clip(t.headline, 70); t.context = Recap.clip(t.context, 120); t.next = Recap.clip(t.next, 70)
        return t.headline.isEmpty || t.next.isEmpty ? nil : t
    }
}

extension Project {
    /// The same project with model-written words in place of the plain recap.
    public func withRecap(_ r: RecapText) -> Project {
        var p = Project(id: id, name: name, branch: branch, away: away, at: at, headline: r.headline,
                        context: r.context.isEmpty ? context : r.context, next: r.next, topic: topic, app: app,
                        agents: agents, steps: steps, sessionId: sessionId, cwd: cwd, desktopSessionId: desktopSessionId)
        p.lastActive = lastActive; p.liveInTerminal = liveInTerminal
        return p
    }
}


/// Reads Codex session files (~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl).
/// The working folder and id sit in the first line (session_meta); messages are response_item records.
public enum CodexTranscript {
    public static func digest(lines: [String]) -> SessionDigest {
        var d = SessionDigest()
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let payload = o["payload"] as? [String: Any] else { continue }
            let type = o["type"] as? String
            if type == "event_msg", let kind = payload["type"] as? String {
                if kind == "task_started" { d.turnOpen = true; d.interrupted = false } else if kind == "task_complete" { d.turnOpen = false } else if kind == "turn_aborted" { d.turnOpen = false; d.interrupted = true }
            }
            if type == "session_meta" {
                if let id = payload["id"] as? String { d.sessionId = id }
                if let cwd = payload["cwd"] as? String { d.cwd = cwd }
                continue
            }
            guard type == "response_item", payload["type"] as? String == "message",
                  let role = payload["role"] as? String, role == "user" || role == "assistant",
                  let text = text(from: payload["content"]), !text.isEmpty else { continue }
            if role == "user", text.hasPrefix("# AGENTS.md") || text.hasPrefix("<") { continue }
            if let ts = o["timestamp"] as? String, let date = iso.date(from: ts) ?? isoPlain.date(from: ts) { d.lastTimestamp = date }
            if role == "user" { d.lastUserText = text; if !Recap.isAcknowledgement(text) { d.lastAsk = text } } else { d.lastAssistantText = text }
            if role == "assistant" { d.interrupted = false }
            d.lastRole = role
            d.recent.append(.init(role: role, text: Recap.clip(text, 420)))
            if d.recent.count > 12 { d.recent.removeFirst() }
        }
        return d
    }

    static func text(from content: Any?) -> String? {
        guard let blocks = content as? [[String: Any]] else { return TranscriptParser.text(from: content) }
        let raw = blocks.compactMap { b -> String? in
            let t = b["type"] as? String
            return t == "input_text" || t == "output_text" ? b["text"] as? String : nil
        }.joined(separator: " ")
        return TranscriptParser.text(from: raw)
    }
}
