import Foundation

/// What we learn from the tail of one Claude Code session file.
public struct SessionDigest: Equatable, Sendable {
    public var sessionId: String?
    public var cwd: String?
    public var branch: String?
    public var title: String?
    public var lastUserText: String?
    /// Your last message with its line breaks, for showing it as written.
    public var lastUserFull: String?
    public var lastAssistantText: String?
    /// The same message with its line breaks, for showing it as written.
    public var lastAssistantFull: String?
    public var lastTimestamp: Date?
    /// "user" or "assistant": who spoke last.
    public var lastRole: String?
    /// The agent's turn has started and not finished: its last record is a tool call, a tool result or your prompt.
    public var turnOpen = false
    /// The newest tool call that has no result yet, while the turn is open. A stale one usually means a permission prompt.
    public var pendingTool: PendingTool?
    /// You stopped the agent (Esc, or Codex's turn was aborted) and have not written since.
    public var interrupted = false
    /// When you stopped it, while `interrupted`.
    public var stoppedAt: Date?
    /// The turn ended on an error (OpenCode, pi), and you have not written since: what went wrong.
    public var failed: String?
    /// The last thing you asked that says something: "yes", "ok go ahead" and "push it" are skipped.
    public var lastAsk: String?
    /// The agent used a tool (edited, ran, searched) somewhere in the part of the session that was read.
    public var didWork = false
    /// While a turn is open: what the agent last said about what it is doing, and the step it is on ("Editing app.js").
    /// Both start over with each prompt you send.
    public var narration: String?
    public var step: String?
    /// Codex: not a thread you started in the app. A `codex exec` run, an MCP call, or a subagent another thread spawned.
    public var headless = false
    /// How the session was started: "cli", "claude-desktop", or "sdk-…" for headless runs like `claude -p`.
    public var entrypoint: String?
    /// When the session began, when the file says (pi's header: the moment pi started it, before its first message).
    public var startedAt: Date?
    /// The project a git worktree belongs to ("perch" for perch/.claude/worktrees/<name>), when the folder is one.
    public var repoName: String?
    /// The last dozen real messages, oldest first, each clipped. Enough to tell small talk from work (`Recap.isTrivial`).
    public var recent: [Line] = []
    public struct Line: Equatable, Sendable { public let role: String; public let text: String }
    /// What the agent did since your last prompt, from its tool calls.
    public var work = Work()
    public init() {}
}

/// What the agent did in one turn, from its tool calls: the facts a card can stand on when its reply says nothing.
public struct Work: Equatable, Sendable {
    /// Each commit's message, its first line ("" when it could not be read), oldest first.
    public var commits: [String] = []
    /// Files it changed, by name, in the order it first touched them.
    public var edited: [String] = []
    /// Files it read, by name.
    public var read: [String] = []
    /// The last command it ran that changes something, in words: "Ran the test suite". Looking around (ls, git log) is not counted.
    public var ran: String?
    public init() {}

    /// It committed, changed files or ran something, rather than only reading and answering.
    public var changedSomething: Bool { !commits.isEmpty || !edited.isEmpty || ran != nil }

    mutating func note(tool: String, input: [String: Any]) {
        let path = ["file_path", "filePath", "path", "notebook_path"].lazy.compactMap { input[$0] as? String }.first
        let name = path.map { ($0 as NSString).lastPathComponent }
        let add = { (f: String, list: inout [String]) in if !f.isEmpty, !list.contains(f) { list.append(f) } }
        switch tool {
        case "Edit", "MultiEdit", "edit", "multiedit", "Write", "write", "NotebookEdit":
            if let name { add(name, &edited) }
        case "apply_patch", "patch":
            // Codex's patch names its files in its own lines: "*** Update File: path".
            let patch = (input["input"] as? String) ?? (input["patch"] as? String) ?? Activity.command(input)
            for f in Self.patched(patch) { add(f, &edited) }
        case "Read", "read":
            if let name { add(name, &read) }
        case "Bash", "bash", "shell", "exec_command", "local_shell", "container.exec", "shell_command":
            let c = Activity.command(input)
            if let m = Self.commitMessage(c) { commits.append(m); return }
            guard !Self.onlyLooks(c) else { return }
            if let about = input["description"] as? String, !about.isEmpty { ran = Activity.past(about) }
            else if let first = c.split(whereSeparator: \.isNewline).first, !first.isEmpty { ran = "Ran `\(Recap.clip(String(first), 48))`" }
        default: break
        }
    }

    /// The message of a `git commit` in a shell command: from a heredoc, or -m "…" / -am '…'. Nil when it is not a commit.
    static func commitMessage(_ c: String) -> String? {
        guard c.range(of: #"\bgit\b[^;&|\n]*\bcommit\b"#, options: .regularExpression) != nil else { return nil }
        if let r = c.range(of: #"<<-?\s*['"]?\w+['"]?[^\n]*\n"#, options: .regularExpression),
           let first = c[r.upperBound...].split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }).first(where: { !$0.isEmpty }) {
            return first
        }
        for pattern in [#"(?:-[a-zA-Z]*m|--message=?)\s*"([^"]*)""#, #"(?:-[a-zA-Z]*m|--message=?)\s*'([^']*)'"#] {
            if let re = try? NSRegularExpression(pattern: pattern), let m = re.firstMatch(in: c, range: NSRange(c.startIndex..., in: c)),
               let r = Range(m.range(at: 1), in: c) {
                return c[r].split(separator: "\n").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            }
        }
        return ""
    }

    /// Commands that only look: listing, reading, searching, git's own reports.
    static func onlyLooks(_ c: String) -> Bool {
        let words = c.trimmingCharacters(in: .whitespaces).split(separator: " ").map(String.init)
        guard let first = words.first.map({ ($0 as NSString).lastPathComponent }) else { return true }
        if ["ls", "cat", "head", "tail", "rg", "grep", "find", "pwd", "echo", "wc", "nl", "which", "file", "stat", "tree", "du", "less", "open"].contains(first) { return true }
        if first == "sed" { return !words.contains { $0.hasPrefix("-i") } }
        if first == "git", let sub = words.dropFirst().first(where: { !$0.hasPrefix("-") }) { return ["status", "log", "diff", "show", "branch", "remote", "rev-parse", "ls-files", "blame"].contains(sub) }
        return false
    }

    static func patched(_ patch: String) -> [String] {
        patch.split(separator: "\n").compactMap { line -> String? in
            guard let r = line.range(of: #"^\*\*\* (Update|Add|Delete) File: "#, options: .regularExpression) else { return nil }
            return (String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces) as NSString).lastPathComponent
        }
    }
}

public struct PendingTool: Equatable, Sendable {
    public let name: String
    /// The question, when the tool asks you one (AskUserQuestion).
    public let question: String?
    /// A Bash call's own timeout, so a long build is not mistaken for a wait.
    public let timeout: TimeInterval?
    /// A question tool's whole input as JSON (every question and its choices), so the card can show them.
    public let questionInput: Data?
    /// When the call was written, when the file says.
    public var at: Date?
    public init(name: String, question: String? = nil, timeout: TimeInterval? = nil, questionInput: Data? = nil) {
        self.name = name; self.question = question; self.timeout = timeout; self.questionInput = questionInput
    }

    /// Tools that wait on you by design: Claude's AskUserQuestion, OpenCode's question.
    public static let questionTools: Set<String> = ["AskUserQuestion", "question"]
    public var isQuestion: Bool { Self.questionTools.contains(name) }

    init(block b: [String: Any]) {
        let name = b["name"] as? String ?? "tool"
        let input = b["input"] as? [String: Any]
        let qs = input?["questions"] as? [[String: Any]]
        var json: Data?
        if Self.questionTools.contains(name) {
            // An older shape carries one bare `question`: the same card, with no choices.
            let whole: [String: Any]? = qs != nil ? input : (input?["question"] as? String).map { ["questions": [["question": $0]]] }
            json = whole.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        }
        self.init(name: name, question: (qs?.first?["question"] as? String) ?? (input?["question"] as? String),
                  timeout: (input?["timeout"] as? Double).map { $0 / 1000 }, questionInput: json)
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
                for b in blocks where b["type"] as? String == "tool_use" {
                    var tool = PendingTool(block: b)
                    tool.at = (o["timestamp"] as? String).flatMap { iso.date(from: $0) ?? isoPlain.date(from: $0) }
                    open.append((b["id"] as? String ?? "", tool)); d.didWork = true
                    if let step = Activity.step(tool: b["name"] as? String ?? "", input: b["input"] as? [String: Any] ?? [:]) { d.step = step }
                    d.work.note(tool: b["name"] as? String ?? "", input: b["input"] as? [String: Any] ?? [:])
                }
            } else if isInterrupt(message?["content"]) {
                d.turnOpen = false; d.interrupted = true; open = []
                d.stoppedAt = (o["timestamp"] as? String).flatMap { iso.date(from: $0) ?? isoPlain.date(from: $0) }
            } else {
                d.turnOpen = true
                let answered = Set(blocks.compactMap { $0["type"] as? String == "tool_result" ? $0["tool_use_id"] as? String : nil })
                open.removeAll { answered.contains($0.id) }
            }
            if !d.turnOpen { open = [] }
            guard let text = text(from: message?["content"]), !text.isEmpty else { continue }
            if let ts = o["timestamp"] as? String, let date = iso.date(from: ts) ?? isoPlain.date(from: ts) { d.lastTimestamp = date }
            if type == "user" { d.lastUserText = text; d.lastUserFull = Self.text(from: message?["content"], keepLines: true); if !Recap.isAcknowledgement(text) { d.lastAsk = text }; d.narration = nil; d.step = nil; d.work = Work() }
            else { d.lastAssistantText = text; d.lastAssistantFull = Self.text(from: message?["content"], keepLines: true); d.narration = text }
            d.interrupted = false; d.stoppedAt = nil
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
    /// `keepLines`: as written, line breaks and all (the card shows it while you reply); otherwise one line, for summaries.
    static func text(from content: Any?, keepLines: Bool = false) -> String? {
        var raw = ""
        if let s = content as? String { raw = s }
        else if let blocks = content as? [[String: Any]] {
            raw = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: keepLines ? "\n\n" : " ")
        }
        raw = strip(raw, open: "<system-reminder>", close: "</system-reminder>")
        raw = strip(raw, open: "<command-name>", close: "</command-name>")
        raw = strip(raw, open: "<command-message>", close: "</command-message>")
        raw = strip(raw, open: "<command-args>", close: "</command-args>")
        raw = strip(raw, open: "<local-command-stdout>", close: "</local-command-stdout>")
        raw = strip(raw, open: "<bash-stdout>", close: "</bash-stdout>")
        raw = strip(raw, open: "<bash-stderr>", close: "</bash-stderr>")
        raw = strip(raw, open: "<bash-input>", close: "</bash-input>")
        let t = keepLines ? raw.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
            : raw.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
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
    public static func project(digest d: SessionDigest, git: GitInfo?, now: Date, calendar: Calendar = .current, desktopSessionId: String? = nil, agent: Agent = .claude, quietFor: TimeInterval? = nil) -> Project? {
        guard let cwd = d.cwd, let last = d.lastTimestamp else { return nil }
        // A chat started without a project lives in a made-up folder ("scratch-2026-10-09-ab78ac"), so its title names it.
        let title = d.title.flatMap { $0.isEmpty ? nil : $0 }, titled = isFolderless(cwd) && title != nil
        let name = titled ? title! : projectName(cwd: cwd, repo: d.repoName)
        let headline = headlineText(d)
        // What the agent did or found is what you need when you come back; your own last prompt is only the fallback.
        // With no sentence worth showing: what it did if it changed something, the answer as written if it only answered.
        let reply = outcome(d.lastAssistantFull ?? d.lastAssistantText)
        let fallback = d.work.changedSomething ? did(d.work) ?? answer(d.lastAssistantText) : answer(d.lastAssistantText) ?? did(d.work)
        let settled = d.failed.map { clip($0, 150) } ?? reply ?? fallback ?? (d.lastAsk ?? d.lastUserText).map { "You asked: “\(clip($0, 120))”" } ?? "Your last session is ready to resume."
        let (status, next) = statusAndNext(d, git, agent: agent, quietFor: quietFor)
        let agents = [AgentStatus(kind: status.kind, text: status.text, app: agent.id)]
        // While it works, the last turn's outcome is old news: say what it is doing now, in its words, or what you asked.
        let working = status.kind == .running
        let context = !working ? settled : outcome(d.narration) ?? (d.lastAsk ?? d.lastUserText).map { "You asked: “\(clip($0, 120))”" } ?? settled
        var p = Project(id: d.sessionId ?? cwd, name: name, branch: d.branch, away: RelativeTime.away(from: last, to: now),
                       at: RelativeTime.clock(last, now: now, calendar: calendar), headline: headline, context: context, next: next,
                       topic: titled ? "" : clip(d.title ?? d.lastAsk ?? d.lastUserText ?? name, 90), app: agent.id, agents: agents,
                       steps: desktopSessionId != nil
                           ? [RestoreStep(icon: "win", text: "Opened the \(agent.short) app"), RestoreStep(icon: "term", text: "Went back to your session")]
                           : [RestoreStep(icon: "term", text: "Opened Terminal in \(name)"), RestoreStep(icon: "term", text: "Resumed your \(agent.name) session")],
                       sessionId: d.sessionId, cwd: cwd, desktopSessionId: desktopSessionId)
        p.lastActive = last
        // A question the transcript shows still open: the card shows it and its choices even when no hook said so.
        if d.turnOpen, let t = d.pendingTool, var q = Ask(pending: t, agent: agent.id) { q.transcriptAt = t.at ?? last; p.ask = q }
        p.stoppedAt = d.interrupted ? d.stoppedAt : nil
        p.now = working ? d.step : nil
        p.said = Recap.said(d.lastAssistantFull ?? d.lastAssistantText)
        p.asked = Recap.asked(d.lastUserFull ?? d.lastUserText)
        return p
    }

    /// The project's name: its folder's, or for a worktree, the project it belongs to. A worktree's own name ("wizardly-
    /// williams-42a0c0") says nothing, so with no project to show the name is empty.
    public static func projectName(cwd: String, repo: String?) -> String {
        if let repo, !repo.isEmpty { return repo }
        let parts = cwd.split(separator: "/").map(String.init)
        guard let i = parts.lastIndex(of: "worktrees"), i >= 1, i < parts.count - 1 else { return parts.last ?? cwd }
        // Claude Code's: <project>/.claude/worktrees/<name>. Codex's: ~/.codex/worktrees/<id>/<project>.
        if parts[i - 1] == ".claude" { return i >= 2 ? parts[i - 2] : "" }
        if parts[i - 1] == ".codex" { return i + 2 < parts.count ? parts[i + 2] : "" }
        return i == parts.count - 2 ? "" : parts.last ?? ""
    }

    /// The project a folder belongs to, from its path alone.
    public static func folderName(_ cwd: String) -> String {
        projectName(cwd: cwd, repo: nil)
    }

    /// The Claude app's scratch workspaces and Codex's dated chat folders: sessions started without picking a project.
    public static func isFolderless(_ cwd: String) -> Bool {
        cwd.contains("/Claude/scratch-workspaces/") || cwd.range(of: #"/Codex/\d{4}-\d{2}-\d{2}/[^/]+/?$"#, options: .regularExpression) != nil
    }

    /// The agent's outcome in a sentence or two, picked from its last message as written. A Summary, TL;DR or Result section
    /// is read first. Code, tables, headings, filler ("Done.", "Sure!"), questions and openers that only announce ("Let me
    /// look…", "Here's what I found:") are skipped; a lead-in that says something ("The hero now fits at phone width:") ends
    /// with a full stop instead. A second sentence joins only from the same paragraph or list, so bullets never run together.
    public static func outcome(_ text: String?) -> String? {
        guard var s = text, !s.isEmpty else { return nil }
        s = s.replacingOccurrences(of: #"```[\s\S]*?(```|$)"#, with: "\n\n", options: .regularExpression)   // code, closed or not
        s = s.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
        if !s.contains("\n") {
            // Squeezed onto one line (a hook's message, the narration): headings and list markers still start a new piece.
            s = s.replacingOccurrences(of: #"(?<=\S)\s+(?=#{1,6}\s|[-*•]\s)"#, with: "\n", options: .regularExpression)
        }
        // Paragraphs and lists, each tagged with whether it sits under a summary heading.
        var blocks: [(list: Bool, summary: Bool, parts: [String])] = [], section = false
        var cur: (list: Bool, parts: [String])?
        func close() { if let c = cur, !c.parts.isEmpty { blocks.append((c.list, section, c.parts)) }; cur = nil }
        let summaryHead = #"^(summary|tl;?dr|result|results|outcome|what changed|what i changed|in short|bottom line|conclusion)\s*(:|$)"#
        for raw in s.components(separatedBy: "\n") {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("|") { close(); continue }   // a blank line ends a paragraph; tables are skipped
            if let h = line.range(of: #"^#{1,6}\s*"#, options: .regularExpression) {
                close(); section = line[h.upperBound...].range(of: summaryHead, options: [.regularExpression, .caseInsensitive]) != nil; continue
            }
            if let r = line.range(of: summaryHead, options: [.regularExpression, .caseInsensitive]) {
                // "Summary:" on its own heads what follows; "TL;DR: the cache…" carries it on the same line.
                close(); section = true
                line = String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                if line.isEmpty { continue }
                line = line.prefix(1).uppercased() + line.dropFirst()
            }
            let item = line.range(of: #"^([-*•>]|\d+[.)])\s+"#, options: .regularExpression)
            if let item { line.removeSubrange(item) }
            if cur?.list != (item != nil) { close(); cur = (item != nil, []) }
            if item != nil || cur!.parts.isEmpty { cur!.parts.append(line) } else { cur!.parts[cur!.parts.count - 1] += " " + line }
        }
        close()
        func sentences(_ t: String) -> [String] {
            t.replacingOccurrences(of: #"(?<=[.!?])\s+(?=[A-Z0-9`“"'(])"#, with: "\u{1}", options: .regularExpression)
                .components(separatedBy: "\u{1}").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        func says(_ t: String, words min: Int = 4) -> Bool {
            t.split(separator: " ").count >= min && !t.hasSuffix("?") && !t.hasSuffix(":") && !isFiller(t) && !announces(t)
        }
        func ended(_ t: String) -> String { t.last.map { ".!?…".contains($0) } == true ? t : t + "." }
        for block in blocks.filter(\.summary) + blocks.filter({ !$0.summary }) {
            let ss = block.list ? block.parts.flatMap(sentences) : sentences(block.parts.joined(separator: " "))
            for (i, t) in ss.enumerated() {
                var first: String
                if says(t) { first = t }
                else if t.hasSuffix(":"), t.split(separator: " ").count >= 5, !announces(t) { first = String(t.dropLast()) }
                else { continue }
                first = ended(first)
                if i + 1 < ss.count, !t.hasSuffix(":"), says(ss[i + 1], words: 3), first.count + ss[i + 1].count < 140 { first += " " + ended(ss[i + 1]) }
                return clip(first, 150)
            }
        }
        return nil
    }

    static let filler = ["sure", "okay", "ok", "got it", "great", "perfect", "alright", "all right", "done", "all done", "fixed", "nice", "good news"]
    static func isFiller(_ t: String) -> Bool {
        let lower = t.lowercased()
        return filler.contains { lower.hasPrefix($0 + ".") || lower.hasPrefix($0 + "!") || lower.hasPrefix($0 + ",") || lower == $0 }
    }
    /// Openers that only announce what comes next: "Let me check…", "I'll walk you through…", "Here's what I found:".
    static func announces(_ t: String) -> Bool {
        let lower = t.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        return ["let me ", "let's ", "i'll ", "i will ", "i'm going to ", "i am going to ", "here's ", "here is ", "here are ", "first,"].contains { lower.hasPrefix($0) }
    }

    /// A reply too short to be an outcome, as written, when it answers: "macOS 26.", "Notch.". Filler and questions are not answers.
    static func answer(_ text: String?) -> String? {
        guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty, !t.contains("```"),
              !t.hasSuffix("?"), !isFiller(t), !announces(t), t.contains(where: \.isLetter) || t.contains(where: \.isNumber) else { return nil }
        return clip(t, 150)
    }

    /// What the agent did in its last turn, most telling first: a commit, the files it changed, what it ran, what it read.
    static func did(_ w: Work) -> String? {
        let files = { (f: [String]) in f.count == 1 ? f[0] : f.count == 2 ? "\(f[0]) and \(f[1])" : "\(f.count) files" }
        if let m = w.commits.last { return m.isEmpty ? "Made a commit" : "Committed: \(clip(m, 100))" }
        if !w.edited.isEmpty { return "Edited " + files(w.edited) }
        if let r = w.ran { return r }
        if !w.read.isEmpty { return "Read " + files(w.read) }
        return nil
    }

    /// A session with nothing in it worth going back to: a hello and a one-line answer.
    public static func isTrivial(_ d: SessionDigest) -> Bool {
        guard !d.turnOpen, d.pendingTool == nil, !d.didWork else { return false }
        // Small talk: you never wrote more than a few words at a time and the agent never did any real work.
        let longestAsk = d.recent.filter { $0.role == "user" }.map(\.text.count).max() ?? 0
        let answered = d.recent.filter { $0.role == "assistant" }.map(\.text.count).reduce(0, +)
        return longestAsk <= 24 && answered < 400
    }

    /// The last message for the card to show while you reply: as written, trimmed, and only its end when it is very long.
    public static func said(_ text: String?) -> String? {
        guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t.count > 4000 ? "\u{2026}" + String(t.suffix(4000)) : t
    }

    /// Your last message for the card to show above it while you reply: as written, and only its start when it is very long.
    public static func asked(_ text: String?) -> String? {
        guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t.count > 1500 ? String(t.prefix(1500)) + "\u{2026}" : t
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
    static func statusAndNext(_ d: SessionDigest, _ git: GitInfo?, agent a: Agent = .claude, quietFor: TimeInterval? = nil) -> ((kind: AgentStatus.Kind, text: String), String) {
        let short = a.short, agent = a.name, quiet = quietFor ?? .infinity
        let working = ((AgentStatus.Kind.running, "\(agent) is working"), "")
        if d.turnOpen, let t = d.pendingTool {
            // Tools that wait on you by design.
            // The card shows the question itself and its choices, so there is no Next row to point at it.
            if t.isQuestion { return ((.needsYou, "\(short) asked you something"), "") }
            if t.name == "ExitPlanMode" { return ((.needsYou, "\(short) has a plan for you"), "Review the plan") }
            // Any other call with no result: running for as long as it plausibly could, then it is waiting for your OK.
            let expected: TimeInterval = ["Bash", "bash"].contains(t.name) ? (t.timeout ?? 120) + 15 : (["Task", "Agent", "task"].contains(t.name) ? 1800 : 30)
            if quiet < expected { return working }
            if quiet < 4 * 3600 { return ((.needsYou, "\(short) is waiting for your OK"), "") }
            return ((.idle, "\(agent) stopped mid-task"), "")
        }
        if d.turnOpen && quiet < runningWindow { return working }
        if d.interrupted { return ((.idle, "You stopped \(short)"), "") }
        if d.failed != nil { return ((.needsYou, "\(short) stopped on an error"), "") }
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
        // Only cues that hand you a step. "Then …" is usually the agent narrating its own plan ("Then run the scanner:").
        let cues = ["next:", "next step:", "next step is to", "still to do:", "remaining:", "to do:", "todo:", "left to do:"]
        let pieces = text.replacingOccurrences(of: "\n", with: ". ").components(separatedBy: CharacterSet(charactersIn: ".!"))
        for raw in pieces.reversed() {
            var t = raw.trimmingCharacters(in: CharacterSet(charactersIn: " -•*\t"))
            guard t.count > 8 else { continue }
            let lower = t.lowercased()
            guard let cue = cues.first(where: { lower.hasPrefix($0) }) else { continue }
            t = String(t.dropFirst(cue.count)).trimmingCharacters(in: CharacterSet(charactersIn: " ,-"))
            // A lead-in to a list, or the agent talking about itself, is not a step for you.
            if t.hasSuffix(":") || t.range(of: #"^(I|I'll|I'm|I've|we|we'll|let me)\b"#, options: [.regularExpression, .caseInsensitive]) != nil { continue }
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
        // One unit ("4h", not "4h 41m"): the line shares the top row with the project's name.
        let ago = String(RelativeTime.away(from: t, to: now).split(separator: " ")[0]), recent = now.timeIntervalSince(t) < 90
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
        return recent ? "Just now" : "\(ago) ago"
    }
}

extension WhileAway {
    /// Where news starts: everything since you last left the Mac, and everything from the last day. Before that is
    /// history, even if you never looked: a question from two days ago is not waiting on you any more.
    public static func newsSince(now: Date, lastLeft: Date?) -> Date {
        min(now.addingTimeInterval(-86_400), lastLeft ?? .distantFuture)
    }
}

extension Project {
    /// The same project with a "needs you" from before `since` read as history. A request the hooks reported still open (`ask`)
    /// always counts; a question only the transcript shows grows old like any guess.
    public func settled(since: Date) -> Project {
        guard needsAttention, ask == nil || ask?.transcriptAt != nil, let t = ask?.transcriptAt ?? lastActive, t < since else { return self }
        var p = self
        p.agents = agents.map { $0.kind == .needsYou ? AgentStatus(kind: .idle, text: $0.text, app: $0.app) : $0 }
        p.ask = nil
        return p
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
                if kind == "task_started" { d.turnOpen = true; d.interrupted = false; d.stoppedAt = nil } else if kind == "task_complete" { d.turnOpen = false }
                else if kind == "turn_aborted" { d.turnOpen = false; d.interrupted = true; d.stoppedAt = (o["timestamp"] as? String).flatMap { iso.date(from: $0) ?? isoPlain.date(from: $0) } }
            }
            if type == "response_item", let kind = payload["type"] as? String, kind.hasSuffix("_call") {
                d.didWork = true
                // Arguments come as a JSON string; a patch comes as plain text.
                var args = (payload["arguments"] as? String).flatMap { (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any] } ?? [:]
                if let patch = payload["input"] as? String, args.isEmpty { args = ["input": patch] }
                if let step = Activity.step(tool: payload["name"] as? String ?? "", input: args) { d.step = step }
                d.work.note(tool: payload["name"] as? String ?? "", input: args)
            }
            if type == "session_meta" {
                if let id = payload["id"] as? String { d.sessionId = id }
                if let cwd = payload["cwd"] as? String { d.cwd = cwd }
                let source = payload["source"]
                if let s = source as? String { d.entrypoint = s }   // "cli" in a terminal, "vscode" in the app
                // Since 0.16x the terminal app also says "vscode"; its originator still says where it runs.
                if let o = payload["originator"] as? String, ["codex-tui", "codex_cli_rs"].contains(o) { d.entrypoint = "cli" }
                if payload["originator"] as? String == "codex_exec" || source is [String: Any] || ["exec", "mcp"].contains(source as? String ?? "") { d.headless = true }
                continue
            }
            guard type == "response_item", payload["type"] as? String == "message",
                  let role = payload["role"] as? String, role == "user" || role == "assistant",
                  let text = text(from: payload["content"]), !text.isEmpty else { continue }
            if role == "user", text.hasPrefix("# AGENTS.md") || text.hasPrefix("<") { continue }
            if let ts = o["timestamp"] as? String, let date = iso.date(from: ts) ?? isoPlain.date(from: ts) { d.lastTimestamp = date }
            if role == "user" { d.lastUserText = text; d.lastUserFull = Self.text(from: payload["content"], keepLines: true); if !Recap.isAcknowledgement(text) { d.lastAsk = text }; d.narration = nil; d.step = nil; d.work = Work() }
            else { d.lastAssistantText = text; d.lastAssistantFull = Self.text(from: payload["content"], keepLines: true); d.narration = text }
            if role == "assistant" { d.interrupted = false; d.stoppedAt = nil }
            d.lastRole = role
            d.recent.append(.init(role: role, text: Recap.clip(text, 420)))
            if d.recent.count > 12 { d.recent.removeFirst() }
        }
        return d
    }

    static func text(from content: Any?, keepLines: Bool = false) -> String? {
        guard let blocks = content as? [[String: Any]] else { return TranscriptParser.text(from: content, keepLines: keepLines) }
        let raw = blocks.compactMap { b -> String? in
            let t = b["type"] as? String
            return t == "input_text" || t == "output_text" ? b["text"] as? String : nil
        }.joined(separator: keepLines ? "\n\n" : " ")
        return TranscriptParser.text(from: raw, keepLines: keepLines)
    }
}

/// What an agent is doing right now, in a few words: the tool call it is on.
public enum Activity {
    /// Nil for calls that say nothing about the work (to-do lists, tool lookups, questions the card shows anyway).
    /// OpenCode and pi name their tools in lowercase ("bash", "read") and their files `filePath` or `path`.
    public static func step(tool: String, input: [String: Any]) -> String? {
        let path = ["file_path", "filePath", "path", "notebook_path"].lazy.compactMap { input[$0] as? String }.first
        let file = { (_: String) in path.map { ($0 as NSString).lastPathComponent } ?? "a file" }
        let quoted = { (k: String) in "“\(Recap.clip(input[k] as? String ?? "", 40))”" }
        switch tool {
        case "Bash", "bash", "shell", "exec_command", "local_shell", "container.exec", "shell_command":
            // Claude Code describes each command in words ("Run the test suite"); that reads better than the command.
            // It is written as an order ("Check the tests"); the Now row says what is happening ("Checking the tests").
            if let about = input["description"] as? String, !about.isEmpty { return Recap.clip(ongoing(about), 70) }
            let c = command(input).split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            return c.isEmpty ? nil : "Running `\(Recap.clip(c, 48))`"
        case "Read", "read", "view_image": return "Reading \(file(""))"
        case "Edit", "MultiEdit", "edit", "multiedit": return "Editing \(file(""))"
        case "Write", "write": return "Writing \(file(""))"
        case "NotebookEdit": return "Editing \(file(""))"
        case "apply_patch", "patch": return "Changing files"
        case "Grep", "grep": return "Searching for \(quoted("pattern"))"
        case "Glob", "glob", "find": return "Looking for \(quoted("pattern"))"
        case "ls", "list": return path.map { "Looking in \(($0 as NSString).lastPathComponent)" } ?? "Looking around"
        case "WebSearch", "web_search", "websearch": return "Searching the web for \(quoted("query"))"
        case "WebFetch", "webfetch": return "Reading \((input["url"] as? String).flatMap { URL(string: $0)?.host } ?? "a page")"
        case "Task", "Agent", "task": return (input["description"] as? String).map { "Helper: \(Recap.clip($0, 60))" } ?? "Working with a helper"
        case "Skill", "skill": return ((input["skill"] ?? input["name"]) as? String).map { "Using \($0)" }
        case "TodoWrite", "TaskCreate", "TaskUpdate", "TaskList", "update_plan", "ToolSearch", "AskUserQuestion", "ExitPlanMode",
             "todowrite", "todoread", "question", "": return nil
        default:
            if tool.hasPrefix("mcp__") { return "Using " + (tool.split(separator: "_").last.map(String.init) ?? tool).replacingOccurrences(of: "-", with: " ") }
            return "Using \(tool)"
        }
    }

    /// "Check how the list is set" becomes "Checking how the list is set": the first word, if it is a capitalised verb, in
    /// its -ing form. Lowercase starts and tool names ("npm test", "Git status") are left as they are.
    public static func ongoing(_ s: String) -> String {
        guard let first = s.split(separator: " ", maxSplits: 1).first.map(String.init), first.count > 1,
              first.first?.isUppercase == true, first.allSatisfy({ $0.isLetter && $0.isASCII }) else { return s }
        let w = first.lowercased()
        guard !w.hasSuffix("ing"), !tools.contains(w) else { return s }
        let irregular = ["be": "being", "see": "seeing", "lie": "lying", "die": "dying", "tie": "tying", "quit": "quitting"]
        let doubles: Set = ["commit", "submit", "admit", "omit", "permit", "refer", "prefer", "begin", "forget", "control", "upset", "regret", "rerun", "unzip", "unwrap"]
        let vowels = Set("aeiou"), c = Array(w)
        let groups = zip(c, [" "] + c.dropLast()).filter { vowels.contains($0.0) && !vowels.contains($0.1) }.count
        let cvc = c.count >= 3 && groups == 1 && !vowels.contains(c[c.count - 1]) && !"wxy".contains(c[c.count - 1])
            && vowels.contains(c[c.count - 2]) && !vowels.contains(c[c.count - 3])
        let g: String
        if let i = irregular[w] { g = i }
        else if doubles.contains(w) || cvc { g = w + String(c[c.count - 1]) + "ing" }
        else if w.hasSuffix("ie") { g = String(w.dropLast(2)) + "ying" }
        else if w.hasSuffix("e"), !w.hasSuffix("ee"), !w.hasSuffix("ye"), !w.hasSuffix("oe") { g = String(w.dropLast()) + "ing" }
        else { g = w + "ing" }
        return g.prefix(1).uppercased() + g.dropFirst() + s.dropFirst(first.count)
    }

    /// "Run the test suite" becomes "Ran the test suite": a command's description as something done. "Rebuild and relaunch"
    /// becomes "Rebuilt and relaunched". One that starts with a tool's name ("npm test", "Git status") becomes "Ran npm test".
    public static func past(_ s: String) -> String {
        let words = s.split(separator: " ").map(String.init)
        guard let first = words.first, first.count > 1, first.first?.isUppercase == true, first.allSatisfy({ $0.isLetter && $0.isASCII }),
              !tools.contains(first.lowercased()), !first.lowercased().hasSuffix("ing"), !first.lowercased().hasSuffix("ed") else {
            let lower = words.first.map { tools.contains($0.lowercased()) ? $0.lowercased() : $0 } ?? ""
            return "Ran " + ([lower] + words.dropFirst()).joined(separator: " ")
        }
        var out = words
        out[0] = pastOf(first.lowercased()).prefix(1).uppercased() + pastOf(first.lowercased()).dropFirst()
        // "Build and run tests": the verb after "and" is done too.
        if out.count > 2, out[1] == "and", out[2].allSatisfy({ $0.isLetter && $0.isLowercase }) { out[2] = pastOf(out[2]) }
        return out.joined(separator: " ")
    }

    static let tools: Set = ["git", "swift", "python", "node", "docker", "xcode", "github", "cargo", "yarn", "pnpm", "brew", "curl", "sqlite", "npm", "gh", "npx", "bun"]

    static func pastOf(_ w: String) -> String {
        let irregular = ["run": "ran", "rerun": "reran", "build": "built", "rebuild": "rebuilt", "make": "made", "write": "wrote", "rewrite": "rewrote",
                         "read": "read", "find": "found", "get": "got", "set": "set", "reset": "reset", "put": "put", "take": "took", "see": "saw",
                         "go": "went", "give": "gave", "keep": "kept", "send": "sent", "do": "did", "redo": "redid", "undo": "undid", "split": "split",
                         "cut": "cut", "let": "let", "quit": "quit", "begin": "began", "spin": "spun", "bring": "brought", "tell": "told", "say": "said",
                         "leave": "left", "hold": "held", "lead": "led", "bind": "bound", "rewind": "rewound", "catch": "caught", "shut": "shut", "hit": "hit"]
        if let i = irregular[w] { return i }
        let doubles: Set = ["commit", "submit", "admit", "omit", "permit", "refer", "prefer", "control", "upset", "regret", "unzip", "unwrap", "format", "program"]
        let vowels = Set("aeiou"), c = Array(w)
        guard c.count > 1 else { return w + "ed" }
        let groups = zip(c, [" "] + c.dropLast()).filter { vowels.contains($0.0) && !vowels.contains($0.1) }.count
        let cvc = c.count >= 3 && groups == 1 && !vowels.contains(c[c.count - 1]) && !"wxy".contains(c[c.count - 1])
            && vowels.contains(c[c.count - 2]) && !vowels.contains(c[c.count - 3])
        if doubles.contains(w) || cvc { return w + String(c[c.count - 1]) + "ed" }
        if w.hasSuffix("e") { return w + "d" }
        if w.hasSuffix("y"), !vowels.contains(c[c.count - 2]) { return String(w.dropLast()) + "ied" }
        return w + "ed"
    }

    /// Codex wraps commands as ["bash", "-lc", "…"]; the last part is what you would read.
    static func command(_ input: [String: Any]) -> String {
        if let c = input["command"] as? String { return c }
        if let parts = input["command"] as? [String] {
            return parts.count >= 3 && ["bash", "zsh", "sh"].contains((parts[0] as NSString).lastPathComponent) ? parts.last! : parts.joined(separator: " ")
        }
        return input["cmd"] as? String ?? ""
    }
}
