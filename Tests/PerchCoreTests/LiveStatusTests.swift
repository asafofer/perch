import Testing
import Foundation
@testable import PerchCore

@Suite struct LiveStatusTests {
    func event(_ name: String, _ json: String, agent: String = "claude", id: String = "r1") -> HookEvent? {
        HookEvent.parse(agent: agent, event: name, body: Data(json.utf8), requestId: id)
    }

    @Test func readsTheEventsPerchUses() {
        #expect(event("UserPromptSubmit", #"{"session_id":"s","prompt":"go"}"#)?.kind == .started)
        #expect(event("Stop", #"{"session_id":"s","last_assistant_message":"Fixed it."}"#)?.kind == .finished(message: "Fixed it."))
        #expect(event("StopFailure", #"{"session_id":"s"}"#)?.kind == .failed)
        #expect(event("Interrupt", #"{"session_id":"s"}"#, agent: "codex")?.kind == .interrupted)
        #expect(event("Notification", #"{"session_id":"s"}"#) == nil)
        #expect(event("Stop", #"{"last_assistant_message":"no session"}"#) == nil)
        #expect(event("Stop", "not json") == nil)
    }

    @Test func aCommandReadsAsWhatItRuns() {
        guard case .asks(let a)? = event("PermissionRequest", #"{"session_id":"s","tool_name":"Bash","tool_input":{"command":"npm run build\nnpm test","description":"Build"}}"#)?.kind else { Issue.record("not an ask"); return }
        #expect(a.title == "Claude wants to run a command"); #expect(a.subject == "npm run build"); #expect(a.kind == .permission); #expect(a.answerable)
    }
    @Test func codexCommandsAreUnwrappedButAnsweredInTheApp() {
        guard case .asks(let a)? = event("PermissionRequest", #"{"session_id":"s","tool_name":"shell","tool_input":{"command":["bash","-lc","rm -rf build"]}}"#, agent: "codex")?.kind else { Issue.record("not an ask"); return }
        #expect(a.title == "Codex wants to run a command"); #expect(a.subject == "rm -rf build"); #expect(!a.answerable)
    }
    @Test func editsWebAndToolsReadPlainly() {
        #expect(Ask.describe(tool: "Edit", input: ["file_path": "/a/b/Settings.swift"]).0 == "edit Settings.swift")
        #expect(Ask.describe(tool: "WebFetch", input: ["url": "https://docs.swift.org/x"]).0 == "open docs.swift.org")
        #expect(Ask.describe(tool: "mcp__linear__save_issue", input: [:]) == ("use issue", "From linear"))
    }

    @Test func aSingleQuestionCanBeAnsweredFromTheNotch() throws {
        let body = #"{"session_id":"s","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Which database?","header":"DB","multiSelect":false,"options":[{"label":"Postgres","description":""},{"label":"SQLite","description":""}]}]}}"#
        guard case .asks(let a)? = event("PermissionRequest", body)?.kind else { Issue.record("not an ask"); return }
        #expect(a.kind == .question); #expect(a.questions.first?.options == ["Postgres", "SQLite"]); #expect(a.answerable)
        let reply = try #require(JSONSerialization.jsonObject(with: a.reply("SQLite")) as? [String: Any])
        let decision = try #require((reply["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any])
        #expect(decision["behavior"] as? String == "allow")
        let input = try #require(decision["updatedInput"] as? [String: Any])
        #expect((input["answers"] as? [String: String]) == ["Which database?": "SQLite"])
        #expect((input["questions"] as? [Any])?.count == 1)   // the original questions go back with the answer
    }
    @Test func severalQuestionsAreAnsweredTogether() throws {
        let body = #"{"session_id":"s","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Backdrop?","header":"Backdrop","options":[{"label":"Studio","description":"Light"},{"label":"Yard"}]},{"question":"Lights?","multiSelect":true,"options":[{"label":"Key"},{"label":"Rim"},{"label":"Fill"}]}]}}"#
        guard case .asks(let a)? = event("PermissionRequest", body)?.kind else { Issue.record("not an ask"); return }
        #expect(a.answerable); #expect(a.questions.count == 2)
        #expect(a.questions[0].header == "Backdrop"); #expect(a.questions[0].notes == ["Light", ""]); #expect(a.questions[1].multiSelect)
        let reply = try #require(JSONSerialization.jsonObject(with: a.reply(answers: ["Backdrop?": "Yard", "Lights?": "Key, Rim"])) as? [String: Any])
        let input = try #require(((reply["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any])?["updatedInput"] as? [String: Any])
        #expect((input["answers"] as? [String: String]) == ["Backdrop?": "Yard", "Lights?": "Key, Rim"])
        #expect((input["questions"] as? [Any])?.count == 2)
    }
    @Test func aQuestionWithoutChoicesIsAnsweredInTheApp() {
        let body = #"{"session_id":"s","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Name it?","options":[]}]}}"#
        guard case .asks(let a)? = event("PermissionRequest", body)?.kind else { Issue.record("not an ask"); return }
        #expect(!a.answerable)
    }
    @Test func allowAndDenyAreHookDecisions() throws {
        let a = Ask(id: "1", agent: "claude", tool: "Bash", input: ["command": "ls"])
        let allow = try #require(JSONSerialization.jsonObject(with: a.reply("allow")) as? [String: Any])
        #expect(((allow["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any])?["behavior"] as? String == "allow")
        let deny = try #require(JSONSerialization.jsonObject(with: a.reply("deny")) as? [String: Any])
        let d = (deny["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any]
        #expect(d?["behavior"] as? String == "deny"); #expect(d?["message"] != nil)
    }

    @Test func statusFollowsTheTurn() {
        let t = Date()
        let ask = Ask(id: "r1", agent: "claude", tool: "Bash", input: ["command": "ls"])
        var s = LiveStatus.apply(HookEvent(agent: "claude", sessionId: "s", kind: .started, at: t), to: nil)
        #expect(s.kind == .working)
        s = LiveStatus.apply(HookEvent(agent: "claude", sessionId: "s", kind: .asks(ask), at: t), to: s)
        #expect(s.kind == .asking); #expect(s.asks.count == 1)
        s = LiveStatus.apply(HookEvent(agent: "claude", sessionId: "s", kind: .toolRan(tool: "Bash"), at: t), to: s)
        #expect(s.kind == .working); #expect(s.asks.isEmpty)   // answered in the app
        s = LiveStatus.apply(HookEvent(agent: "claude", sessionId: "s", kind: .asks(ask), at: t), to: s)
        s.settle("r1", at: t)
        #expect(s.kind == .working)
        s = LiveStatus.apply(HookEvent(agent: "claude", sessionId: "s", kind: .finished(message: "Done. The build passes now."), at: t), to: s)
        #expect(s.kind == .finished)
    }

    @Test func liveStatusOverridesTheTranscriptGuess() {
        let p = Project(id: "s", name: "site", branch: nil, away: "1m", at: "", headline: "H.", context: "C", next: "Old next", topic: "", app: "claude",
                        agents: [AgentStatus(kind: .running, text: "Claude Code is working")], steps: [])
        var live = LiveStatus(kind: .asking, at: Date()); live.asks = [Ask(id: "1", agent: "claude", tool: "Bash", input: ["command": "ls"])]
        let asking = p.applying(live)
        #expect(asking.status.kind == "attention"); #expect(asking.ask?.subject == "ls"); #expect(asking.next == "")
        live = LiveStatus(kind: .finished, at: Date()); live.outcome = "All set. The hero now fits at phone width."
        let done = p.applying(live)
        #expect(done.status.kind == "done"); #expect(done.context == "The hero now fits at phone width."); #expect(done.ask == nil)
        #expect(p.applying(LiveStatus(kind: .failed, at: Date())).status.text == "Claude stopped on an error")
    }

    /// Stop in the Claude app sends no hook: the last one said working. The transcript's interruption, after it, wins.
    @Test func aStopInTheAppBeatsTheLastHook() {
        let lines = [
            #"{"type":"user","sessionId":"s","cwd":"/Users/a/site","timestamp":"2026-10-10T07:56:00.000Z","message":{"content":"run it locally"}}"#,
            #"{"type":"assistant","sessionId":"s","timestamp":"2026-10-10T07:56:39.510Z","message":{"stop_reason":"tool_use","content":[{"type":"text","text":"Reopening the app."},{"type":"tool_use","id":"t1","name":"Bash"}]}}"#,
            #"{"type":"user","timestamp":"2026-10-10T07:56:40.574Z","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"rejected"}]}}"#,
            #"{"type":"user","timestamp":"2026-10-10T07:56:40.575Z","message":{"content":[{"type":"text","text":"[Request interrupted by user for tool use]"}]}}"#,
        ]
        let d = TranscriptParser.digest(lines: lines)
        let p = Recap.project(digest: d, git: nil, now: d.lastTimestamp!.addingTimeInterval(60))!
        #expect(p.stoppedAt != nil); #expect(p.status.text == "You stopped Claude")
        let lastTool = d.lastTimestamp!.addingTimeInterval(-5)
        #expect(!LiveStatus(kind: .working, at: lastTool).holds(for: p))
        // Writing again starts a new turn: the stop is over and the hooks speak for it again.
        let again = TranscriptParser.digest(lines: lines + [#"{"type":"user","timestamp":"2026-10-10T07:57:00.000Z","message":{"content":"try again"}}"#])
        let q = Recap.project(digest: again, git: nil, now: again.lastTimestamp!)!
        #expect(q.stoppedAt == nil); #expect(LiveStatus(kind: .working, at: again.lastTimestamp!).holds(for: q))
    }
}

@Suite struct OtherAgentsLiveTests {
    @Test func openCodeAsksArePermissionsAndQuestionsPerchCanAnswer() {
        let body = Data(#"{"session_id":"ses_1","tool_name":"bash","tool_input":{"command":"rm -rf dist && bun run build"}}"#.utf8)
        guard case .asks(let a)? = HookEvent.parse(agent: "opencode", event: "PermissionRequest", body: body, requestId: "r")?.kind else { Issue.record("no ask"); return }
        #expect(a.title == "OpenCode wants to run a command"); #expect(a.subject == "rm -rf dist && bun run build"); #expect(a.answerable)
        let q = Data(#"{"session_id":"ses_1","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Tab leaves the table?","header":"Tab","options":[{"label":"Yes"},{"label":"No"}]}]}}"#.utf8)
        guard case .asks(let b)? = HookEvent.parse(agent: "opencode", event: "PermissionRequest", body: q, requestId: "r2")?.kind else { Issue.record("no question"); return }
        #expect(b.kind == .question); #expect(b.answerable); #expect(b.questions.first?.options == ["Yes", "No"])
    }

    @Test func aPiPromptIsShownAndAnsweredInTheTerminal() {
        let body = Data(#"{"session_id":"019f","tool_name":"pi_prompt","tool_input":{"question":"Overwrite failed.txt?","kind":"confirm"}}"#.utf8)
        guard case .asks(let a)? = HookEvent.parse(agent: "pi", event: "PermissionRequest", body: body, requestId: "r")?.kind else { Issue.record("no ask"); return }
        #expect(a.kind == .question); #expect(a.title == "pi asked you something"); #expect(a.subject == "Overwrite failed.txt?"); #expect(!a.answerable)
        #expect(HookEvent.parse(agent: "pi", event: "Stop", body: Data(#"{"session_id":"019f","last_assistant_message":"Done."}"#.utf8), requestId: "x")?.kind == .finished(message: "Done."))
    }
}
