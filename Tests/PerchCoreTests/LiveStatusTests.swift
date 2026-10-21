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
    @Test func theRowSaysTheCommandWithoutItsOutputPlumbing() {
        #expect(Ask.plainCommand("npm run build 2>&1 | tail -20") == "npm run build")
        #expect(Ask.plainCommand(#"npm run build 2>&1 | tail -n 30; echo "EXIT: ${PIPESTATUS[0]}""#) == "npm run build")
        #expect(Ask.plainCommand("swift test 2>/dev/null | head -n 40") == "swift test")
        #expect(Ask.plainCommand("git log | grep fix") == "git log | grep fix")   // a pipe that does work stays
        #expect(Ask.plainCommand("echo hi") == "echo hi")
        let a = Ask(id: "r", agent: "claude", tool: "Bash", input: ["command": "npm run build 2>&1 | tail -20"])
        #expect(a.subject == "npm run build 2>&1 | tail -20"); #expect(a.brief == "npm run build")   // the card keeps it all
        #expect(Ask(id: "r", agent: "claude", tool: "Edit", input: ["file_path": "/a/x 2>&1"]).brief == "/a/x 2>&1")
    }
    @Test func editsWebAndToolsReadPlainly() {
        #expect(Ask.describe(tool: "Edit", input: ["file_path": "/a/b/Settings.swift"]).0 == "edit Settings.swift")
        #expect(Ask.describe(tool: "WebFetch", input: ["url": "https://docs.swift.org/x"]).0 == "open docs.swift.org")
        #expect(Ask.describe(tool: "mcp__linear__save_issue", input: [:]) == ("use issue", "From linear"))
    }

    @Test func anOpenCodeRequestOutlivesAToolRunBesideIt() throws {
        // OpenCode asked to run the build and, in the same step, ran a tool that needs no OK: that tool finishing settles nothing.
        let ask = try #require(event("PermissionRequest", #"{"session_id":"s","tool_name":"bash","tool_input":{"command":"npm run build"}}"#, agent: "opencode"))
        var s = LiveStatus.apply(ask, to: nil)
        s = LiveStatus.apply(try #require(event("PostToolUse", #"{"session_id":"s","tool_name":"codegraph_codegraph_node"}"#, agent: "opencode")), to: s)
        #expect(s.kind == .asking); #expect(s.asks.map(\.id) == ["r1"])
        // Answered: its plugin lets the request go, and only then is it settled.
        s.settle("r1", at: Date())
        #expect(s.kind == .working); #expect(s.asks.isEmpty)
        // A Claude tool run after a request still means it was answered.
        let claude = LiveStatus.apply(try #require(event("PostToolUse", #"{"session_id":"s","tool_name":"Bash"}"#)),
                                      to: LiveStatus.apply(try #require(event("PermissionRequest", #"{"session_id":"s","tool_name":"Bash","tool_input":{"command":"ls"}}"#)), to: nil))
        #expect(claude.kind == .working); #expect(claude.asks.isEmpty)
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

    /// The turn that started helpers in the background ends (Stop), and the helpers go on: Claude Code says so with no hook,
    /// so what the transcript knows stands.
    @Test func aStopWithWorkLeftInTheBackgroundIsNotDone() {
        var p = Project(id: "s", name: "rizz", branch: nil, away: "1m", at: "", headline: "H.", context: "Started helpers for M4, M5 and M8.", next: "", topic: "", app: "claude",
                        agents: [AgentStatus(kind: .running, text: "Claude Code is working")], steps: [])
        p.waiting = true; p.now = "Waiting on 3 helpers"
        var stop = LiveStatus(kind: .finished, at: Date()); stop.outcome = "Started helpers for M4, M5 and M8."
        let still = p.applying(stop)
        #expect(still.status.kind == "running"); #expect(still.now == "Waiting on 3 helpers"); #expect(still.context == "Started helpers for M4, M5 and M8.")
        p.waiting = false
        #expect(p.applying(stop).status.kind == "done")
    }

    /// Helpers send their hooks with the session's id. Their tool calls must not answer the question the session asks.
    @Test func aHelperAtWorkDoesNotAnswerTheSessionsQuestion() {
        let t = Date()
        #expect(event("PostToolUse", #"{"session_id":"s","tool_name":"Bash","agent_id":"a1","agent_type":"general-purpose"}"#)?.helper == "a1")
        #expect(event("PostToolUse", #"{"session_id":"s","tool_name":"Bash"}"#)?.helper == nil)
        guard case .asks(let own)? = event("PermissionRequest", #"{"session_id":"s","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Ship it?","options":[{"label":"Yes"},{"label":"No"}]}]}}"#, id: "q")?.kind,
              case .asks(let helpers)? = event("PermissionRequest", #"{"session_id":"s","agent_id":"a1","tool_name":"Bash","tool_input":{"command":"rm -rf dist"}}"#, id: "h")?.kind
        else { Issue.record("no ask"); return }
        #expect(own.helper == nil); #expect(helpers.helper == "a1")
        func ran(_ helper: String?, _ at: Date) -> HookEvent { var e = HookEvent(agent: "claude", sessionId: "s", kind: .toolRan(tool: "Bash"), at: at); e.helper = helper; return e }
        var s = LiveStatus.apply(HookEvent(agent: "claude", sessionId: "s", kind: .asks(own), at: t), to: nil)
        s = LiveStatus.apply(HookEvent(agent: "claude", sessionId: "s", kind: .asks(helpers), at: t), to: s)
        // Another helper's tool: nothing changes, not even when the session last spoke.
        s = LiveStatus.apply(ran("a2", t.addingTimeInterval(5)), to: s)
        #expect(s.kind == .asking); #expect(s.asks.map(\.id) == ["q", "h"]); #expect(s.at == t)
        // The helper that asked goes on: its request was answered, the session's own question is still open.
        s = LiveStatus.apply(ran("a1", t.addingTimeInterval(6)), to: s)
        #expect(s.kind == .asking); #expect(s.asks.map(\.id) == ["q"])
        // The session itself goes on: its question was answered.
        s = LiveStatus.apply(ran(nil, t.addingTimeInterval(7)), to: s)
        #expect(s.kind == .working); #expect(s.asks.isEmpty)
        // After the turn's Stop, a helper still at work keeps the session at work.
        s = LiveStatus.apply(HookEvent(agent: "claude", sessionId: "s", kind: .finished(message: "Started the helpers."), at: t.addingTimeInterval(8)), to: s)
        s = LiveStatus.apply(ran("a1", t.addingTimeInterval(9)), to: s)
        #expect(s.kind == .working)
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

@Suite struct HookPidTests {
    @Test func aHookSaysWhichProcessSentIt() {
        let body = Data(#"{"session_id":"019f","pid":4242}"#.utf8)
        #expect(HookEvent.parse(agent: "pi", event: "UserPromptSubmit", body: body, requestId: "r")?.pid == 4242)
        #expect(HookEvent.parse(agent: "claude", event: "Stop", body: Data(#"{"session_id":"s"}"#.utf8), requestId: "r", pid: 77)?.pid == 77)
        #expect(HookEvent.parse(agent: "claude", event: "Stop", body: Data(#"{"session_id":"s"}"#.utf8), requestId: "r")?.pid == nil)
    }

    // MARK: a question the hooks never reported (Bypass permissions, or no hooks installed)
    func questionProject(at asked: Date) -> Project {
        let lines = [#"{"type":"user","sessionId":"s2","cwd":"/Users/a/app","timestamp":"2026-10-07T09:00:00.000Z","message":{"content":"plan it"}}"#,
                     #"{"type":"assistant","timestamp":"2026-10-07T09:00:05.000Z","message":{"stop_reason":"tool_use","content":[{"type":"tool_use","id":"q","name":"AskUserQuestion","input":{"questions":[{"question":"Pick one?","options":[{"label":"A"},{"label":"B"}]}]}}]}}"#]
        var p = Recap.project(digest: TranscriptParser.digest(lines: lines), git: nil, now: asked, quietFor: 1)!
        p.ask?.transcriptAt = asked
        return p
    }
    @Test func aHookThatCameBeforeTheTranscriptsOpenQuestionDoesNotHideIt() {
        let asked = Date(), p = questionProject(at: asked)
        let before = LiveStatus(kind: .working, at: asked.addingTimeInterval(-4))   // the last tool's PostToolUse
        let shown = p.applying(before)
        #expect(shown.ask?.questions.first?.options == ["A", "B"]); #expect(shown.status.text == "Claude asked you something")
    }
    @Test func aHookThatCameAfterTheQuestionMovesOn() {
        let asked = Date(), p = questionProject(at: asked)
        let after = LiveStatus(kind: .working, at: asked.addingTimeInterval(20))   // answered: its PostToolUse
        #expect(p.applying(after).ask == nil); #expect(p.applying(after).status.kind == "running")
    }
    @Test func aRequestTheHooksDidReportIsTheOneThatCanBeAnswered() {
        let asked = Date(), p = questionProject(at: asked)
        var live = LiveStatus(kind: .asking, at: asked.addingTimeInterval(1))
        guard case .asks(let a)? = HookEvent.parse(agent: "claude", event: "PermissionRequest", body: Data(#"{"session_id":"s2","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Pick one?","options":[{"label":"A"},{"label":"B"}]}]}}"#.utf8), requestId: "r9")?.kind else { Issue.record("not an ask"); return }
        live.asks = [a]
        #expect(p.applying(live).ask?.answerable == true)
    }

    /// Bypass permissions mode sends no PermissionRequest for a question; the PreToolUse hook is how Perch answers it there.
    @Test func aQuestionFromThePreToolUseHookIsAnsweredInThatHooksShape() throws {
        let body = Data(#"{"session_id":"s3","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Colour?","options":[{"label":"Red"},{"label":"Blue"}]}]}}"#.utf8)
        guard case .asks(let a)? = HookEvent.parse(agent: "claude", event: "PreToolUse", body: body, requestId: "p1")?.kind else { Issue.record("not an ask"); return }
        #expect(a.answerable); #expect(a.viaPreToolUse)
        let out = try #require(JSONSerialization.jsonObject(with: a.reply("Red")) as? [String: Any])
        let h = try #require(out["hookSpecificOutput"] as? [String: Any])
        #expect(h["hookEventName"] as? String == "PreToolUse"); #expect(h["permissionDecision"] as? String == "allow")
        let input = try #require(h["updatedInput"] as? [String: Any])
        #expect((input["answers"] as? [String: String]) == ["Colour?": "Red"])
    }
    @Test func preToolUseForAnythingElseIsIgnored() {
        #expect(HookEvent.parse(agent: "claude", event: "PreToolUse", body: Data(#"{"session_id":"s","tool_name":"Bash","tool_input":{"command":"ls"}}"#.utf8), requestId: "p2") == nil)
    }
}
