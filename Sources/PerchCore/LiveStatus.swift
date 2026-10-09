import Foundation

/// Something Claude Code or Codex told Perch through a hook, the moment it happened.
public struct HookEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// You sent a prompt: the agent is working.
        case started
        /// A tool ran, so the agent is working (and any question about it has been answered).
        case toolRan(tool: String)
        /// The agent asks before going on: permission for a tool, a question, or a plan.
        case asks(Ask)
        /// The turn is over. `message` is the agent's last reply.
        case finished(message: String?)
        /// The turn ended on an error (rate limit, server error).
        case failed
        /// You stopped it.
        case interrupted
    }
    public let agent: String        // "claude" or "codex"
    public let sessionId: String
    public let kind: Kind
    public let at: Date
    public init(agent: String, sessionId: String, kind: Kind, at: Date = Date()) {
        self.agent = agent; self.sessionId = sessionId; self.kind = kind; self.at = at
    }

    /// Reads a hook's JSON body. `event` is the hook event name from the URL. Nil for anything Perch does not use.
    public static func parse(agent: String, event: String, body: Data, requestId: String, at: Date = Date()) -> HookEvent? {
        guard let o = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let session = o["session_id"] as? String, !session.isEmpty else { return nil }
        let kind: Kind
        switch event {
        case "UserPromptSubmit": kind = .started
        case "PostToolUse": kind = .toolRan(tool: o["tool_name"] as? String ?? "")
        case "PermissionRequest":
            kind = .asks(Ask(id: requestId, agent: agent, tool: o["tool_name"] as? String ?? "tool", input: o["tool_input"] as? [String: Any] ?? [:]))
        case "Stop": kind = .finished(message: o["last_assistant_message"] as? String)
        case "StopFailure": kind = .failed
        case "Interrupt": kind = .interrupted
        default: return nil
        }
        return HookEvent(agent: agent, sessionId: session, kind: kind, at: at)
    }
}

/// What the agent is asking for, put in words for the card.
public struct Ask: Equatable, Sendable {
    public enum Kind: String, Sendable { case permission, question, plan }
    public let id: String
    public let agent: String
    public let tool: String
    public let kind: Kind
    /// "Claude wants to run a command", "Codex asked you something".
    public let title: String
    /// The command, the file, the host, or the question itself.
    public let subject: String
    /// Every question the agent asked, in order. Empty unless this is a question.
    public let questions: [Question]
    /// Perch can answer this from the notch. Codex approvals are answered in the app.
    public let answerable: Bool

    /// One question, its choices by label, and what each choice means as the agent described it.
    public struct Question: Equatable, Sendable {
        public let text: String
        public let header: String
        public let multiSelect: Bool
        public let options: [String]
        public let notes: [String]
    }
    /// The tool's input, as JSON, so an answer can be sent back with it.
    public let inputJSON: Data

    public init(id: String, agent: String, tool: String, input: [String: Any]) {
        self.id = id; self.agent = agent; self.tool = tool
        inputJSON = (try? JSONSerialization.data(withJSONObject: input)) ?? Data("{}".utf8)
        let who = agent == "codex" ? "Codex" : "Claude"
        switch tool {
        case "AskUserQuestion":
            let qs = (input["questions"] as? [[String: Any]] ?? []).map { q -> Question in
                let opts = (q["options"] as? [[String: Any]] ?? []).filter { $0["label"] is String }
                return Question(text: q["question"] as? String ?? "A question for you", header: q["header"] as? String ?? "",
                                multiSelect: q["multiSelect"] as? Bool ?? false,
                                options: opts.compactMap { $0["label"] as? String }, notes: opts.map { $0["description"] as? String ?? "" })
            }
            kind = .question; title = "\(who) asked you something"; subject = Recap.clip(qs.first?.text ?? "A question for you", 140)
            questions = qs
            // Up to nine choices fit the number keys; a question with none can only be answered in the app.
            answerable = agent == "claude" && !qs.isEmpty && qs.allSatisfy { (1...9).contains($0.options.count) }
        case "ExitPlanMode":
            kind = .plan; title = "\(who) has a plan for you"
            subject = Ask.firstLine(input["plan"] as? String) ?? "Read it before it starts"
            questions = []; answerable = false
        default:
            kind = .permission; questions = []
            let (verb, what) = Ask.describe(tool: tool, input: input)
            title = "\(who) wants to \(verb)"; subject = what
            answerable = agent == "claude"
        }
    }

    /// The plan's first real line, without its markdown heading marks.
    static func firstLine(_ text: String?) -> String? {
        guard let text else { return nil }
        let line = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "#*-> \t")) }.first { !$0.isEmpty }
        return line.map { Recap.clip($0, 120) }
    }

    /// A verb for the title and the thing it acts on, in plain words.
    static func describe(tool: String, input: [String: Any]) -> (String, String) {
        let file = { (k: String) in ((input[k] as? String).map { ($0 as NSString).lastPathComponent }) ?? "a file" }
        func command() -> String {
            if let c = input["command"] as? String { return c }
            if let parts = input["command"] as? [String] {
                // Codex wraps commands as ["bash", "-lc", "…"]; the last part is what you would read.
                return parts.count >= 3 && ["bash", "zsh", "sh"].contains((parts[0] as NSString).lastPathComponent) ? parts.last! : parts.joined(separator: " ")
            }
            return input["cmd"] as? String ?? ""
        }
        switch tool {
        case "Bash", "shell", "exec_command", "local_shell", "container.exec":
            let c = command().split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            return ("run a command", Recap.clip(c.isEmpty ? (input["description"] as? String ?? "a command") : c, 140))
        case "Edit", "MultiEdit": return ("edit \(file("file_path"))", input["file_path"] as? String ?? "")
        case "Write": return ("write \(file("file_path"))", input["file_path"] as? String ?? "")
        case "NotebookEdit": return ("edit \(file("notebook_path"))", input["notebook_path"] as? String ?? "")
        case "apply_patch": return ("change files", Recap.clip(input["description"] as? String ?? "", 140))
        case "WebFetch":
            let host = (input["url"] as? String).flatMap { URL(string: $0)?.host } ?? "a page"
            return ("open \(host)", input["url"] as? String ?? "")
        case "WebSearch": return ("search the web", "“\(Recap.clip(input["query"] as? String ?? "", 100))”")
        default:
            if tool.hasPrefix("mcp__") {
                let parts = tool.split(separator: "_", omittingEmptySubsequences: true)
                let name = parts.last.map(String.init) ?? tool, server = parts.count > 2 ? String(parts[1]) : ""
                return ("use \(name)", server.isEmpty ? "" : "From \(server)")
            }
            return ("use \(tool)", Recap.clip(input["description"] as? String ?? "", 140))
        }
    }

    /// The hook reply that answers a question: each question's text to the chosen label (several joined with commas).
    public func reply(answers: [String: String]) -> Data {
        var input = (try? JSONSerialization.jsonObject(with: inputJSON)) as? [String: Any] ?? [:]
        input["answers"] = answers
        let out: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": ["behavior": "allow", "updatedInput": input]]]
        return (try? JSONSerialization.data(withJSONObject: out)) ?? Data()
    }

    /// The hook reply that answers this request. `choice` is "allow", "deny", or, for a single question, an option label.
    public func reply(_ choice: String) -> Data {
        var decision: [String: Any]
        if kind == .question, let q = questions.first, choice != "deny" {
            return reply(answers: [q.text: choice])
        } else if choice == "allow" {
            decision = ["behavior": "allow"]
        } else {
            decision = ["behavior": "deny", "message": "The user said no from Perch."]
        }
        let out: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
        return (try? JSONSerialization.data(withJSONObject: out)) ?? Data()
    }
}

/// The latest thing a session's hooks said. It beats reading the transcript, which can only guess.
public struct LiveStatus: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case working, finished, asking, stopped, failed }
    public var kind: Kind
    public var at: Date
    /// Open requests, oldest first. The card shows the newest.
    public var asks: [Ask] = []
    public var outcome: String?

    public init(kind: Kind, at: Date) { self.kind = kind; self.at = at }

    /// Folds one event into the session's state. Anything that moves the turn along settles the open requests.
    public static func apply(_ e: HookEvent, to s: LiveStatus?) -> LiveStatus {
        var s = s ?? LiveStatus(kind: .working, at: e.at)
        s.at = e.at
        switch e.kind {
        case .started: s.kind = .working; s.asks = []; s.outcome = nil
        case .toolRan: s.asks = []; s.kind = .working
        case .asks(let a): s.asks.removeAll { $0.id == a.id }; s.asks.append(a); s.kind = .asking
        case .finished(let m): s.kind = .finished; s.asks = []; s.outcome = m
        case .failed: s.kind = .failed; s.asks = []
        case .interrupted: s.kind = .stopped; s.asks = []
        }
        return s
    }

    /// A request was answered (here or in the app) or abandoned.
    public mutating func settle(_ askId: String, at: Date) {
        guard asks.contains(where: { $0.id == askId }) else { return }
        asks.removeAll { $0.id == askId }
        if asks.isEmpty, kind == .asking { kind = .working; self.at = at }
    }
}

extension Project {
    /// The same project with what its hooks said in place of what the transcript suggested.
    public func applying(_ live: LiveStatus) -> Project {
        let who = app == "codex" ? "Codex" : "Claude"
        let status: AgentStatus
        var next = self.next, context = self.context
        switch live.kind {
        case .working: status = AgentStatus(kind: .running, text: "\(app == "codex" ? "Codex" : "Claude Code") is working", app: app); next = ""
        case .asking:
            let a = live.asks.last
            status = AgentStatus(kind: .needsYou, text: a?.title ?? "\(who) needs you", app: app); next = ""
        case .finished:
            status = AgentStatus(kind: .done, text: "\(who) finished", app: app)
            if let o = Recap.outcome(live.outcome) { context = o }
        case .stopped: status = AgentStatus(kind: .idle, text: "You stopped \(who)", app: app); next = ""
        case .failed: status = AgentStatus(kind: .needsYou, text: "\(who) stopped on an error", app: app); next = ""
        }
        var p = Project(id: id, name: name, branch: branch, away: away, at: at, headline: headline, context: context, next: next,
                        topic: topic, app: app, agents: [status], steps: steps, sessionId: sessionId, cwd: cwd, desktopSessionId: desktopSessionId)
        p.lastActive = max(lastActive ?? live.at, live.at)
        p.ask = live.kind == .asking ? live.asks.last : nil
        p.focusedAt = focusedAt
        return p
    }
}
