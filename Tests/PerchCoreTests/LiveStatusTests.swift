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
        #expect(a.kind == .question); #expect(a.options == ["Postgres", "SQLite"]); #expect(a.answerable)
        let reply = try #require(JSONSerialization.jsonObject(with: a.reply("SQLite")) as? [String: Any])
        let decision = try #require((reply["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any])
        #expect(decision["behavior"] as? String == "allow")
        let input = try #require(decision["updatedInput"] as? [String: Any])
        #expect((input["answers"] as? [String: String]) == ["Which database?": "SQLite"])
        #expect((input["questions"] as? [Any])?.count == 1)   // the original questions go back with the answer
    }
    @Test func multiPartQuestionsAreAnsweredInTheApp() {
        let body = #"{"session_id":"s","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"A?","options":[{"label":"x"},{"label":"y"}]},{"question":"B?","options":[{"label":"x"},{"label":"y"}]}]}}"#
        guard case .asks(let a)? = event("PermissionRequest", body)?.kind else { Issue.record("not an ask"); return }
        #expect(a.options.isEmpty); #expect(!a.answerable)
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
}
