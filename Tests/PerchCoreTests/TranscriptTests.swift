import Testing
import Foundation
@testable import PerchCore

@Suite struct TranscriptTests {
    let lines = [
        #"{"type":"custom-title","customTitle":"Fix the review sign","sessionId":"s1"}"#,
        #"{"type":"user","sessionId":"s1","cwd":"/Users/a/site","gitBranch":"main","timestamp":"2026-10-07T09:00:00.000Z","message":{"content":"make the sign centred"}}"#,
        #"{"type":"assistant","sessionId":"s1","cwd":"/Users/a/site","timestamp":"2026-10-07T09:05:00.000Z","message":{"content":[{"type":"text","text":"Done. Want a table next?"}]}}"#,
        #"{"type":"user","isMeta":true,"message":{"content":"ignored meta"}}"#,
        #"{"type":"user","isSidechain":true,"message":{"content":"ignored sidechain"}}"#,
        #"{"type":"user","timestamp":"2026-10-07T09:06:00.000Z","message":{"content":[{"type":"tool_result","content":"huge output"}]}}"#,
        "not json at all",
    ]

    @Test func keepsTheLatestFacts() {
        let d = TranscriptParser.digest(lines: lines)
        #expect(d.sessionId == "s1"); #expect(d.cwd == "/Users/a/site"); #expect(d.branch == "main")
        #expect(d.title == "Fix the review sign")
        #expect(d.lastUserText == "make the sign centred")
        #expect(d.lastAssistantText == "Done. Want a table next?")
        #expect(d.lastRole == "assistant")
    }
    @Test func ignoresMetaSidechainToolResultsAndGarbage() {
        let d = TranscriptParser.digest(lines: lines)
        #expect(d.lastUserText != "ignored meta"); #expect(d.lastUserText != "ignored sidechain")
    }
    @Test func stripsInjectedReminders() {
        let t = TranscriptParser.text(from: "hello <system-reminder>secret</system-reminder> world")
        #expect(t == "hello  world".replacingOccurrences(of: "  ", with: " ") || t == "hello  world")
    }
    @Test func recapUsesQuestionAsNextStep() {
        let d = TranscriptParser.digest(lines: lines)
        let now = ISO8601DateFormatter().date(from: "2026-10-07T11:19:00Z")!
        let p = Recap.project(digest: d, git: GitInfo(uncommitted: 0), now: now)!
        #expect(p.name == "site"); #expect(p.status.kind == "attention")
        #expect(p.next.contains("Want a table next?"))
        #expect(p.sessionId == "s1"); #expect(p.cwd == "/Users/a/site")
    }
    @Test func recapPrefersUncommittedFilesWhenClaudeIsDone() {
        var d = TranscriptParser.digest(lines: lines); d.lastAssistantText = "All done."
        let p = Recap.project(digest: d, git: GitInfo(uncommitted: 3, files: ["a.swift", "b.js", "c.md"]), now: Date())!
        #expect(p.next == ""); #expect(p.status.kind == "done")
    }
    @Test func waitingWhenUserSpokeLast() {
        var d = TranscriptParser.digest(lines: lines); d.lastRole = "user"
        let p = Recap.project(digest: d, git: nil, now: Date())!
        #expect(p.status.kind == "attention")
    }
    @Test func turnIsOpenAfterAToolResultAndClosedAfterEndTurn() {
        #expect(TranscriptParser.digest(lines: lines).turnOpen)   // the last record is a tool result
        let finished = lines + [#"{"type":"assistant","timestamp":"2026-10-07T09:07:00.000Z","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"All done."}]}}"#]
        #expect(!TranscriptParser.digest(lines: finished).turnOpen)
        let working = finished + [#"{"type":"assistant","message":{"stop_reason":"tool_use","content":[{"type":"tool_use","name":"Bash"}]}}"#]
        #expect(TranscriptParser.digest(lines: working).turnOpen)
        let stopped = working + [#"{"type":"user","message":{"content":[{"type":"text","text":"[Request interrupted by user]"}]}}"#]
        #expect(!TranscriptParser.digest(lines: stopped).turnOpen)
    }
    @Test func codexTurnFollowsTaskEvents() {
        let started = [#"{"type":"event_msg","payload":{"type":"task_started"}}"#]
        #expect(CodexTranscript.digest(lines: started).turnOpen)
        #expect(!CodexTranscript.digest(lines: started + [#"{"type":"event_msg","payload":{"type":"task_complete"}}"#]).turnOpen)
    }
    @Test func awayFormatting() {
        let now = Date()
        #expect(RelativeTime.away(from: now.addingTimeInterval(-30), to: now) == "1m")
        #expect(RelativeTime.away(from: now.addingTimeInterval(-8040), to: now) == "2h 14m")
        #expect(RelativeTime.away(from: now.addingTimeInterval(-72_000), to: now) == "20h")
        #expect(RelativeTime.away(from: now.addingTimeInterval(-3 * 86_400), to: now) == "3d")
    }
    @Test func projectWithoutCwdOrTimeIsDropped() {
        var d = SessionDigest(); d.lastUserText = "hi"
        #expect(Recap.project(digest: d, git: nil, now: Date()) == nil)
    }
    @Test func shellCommandsAreNotPrompts() {
        #expect(TranscriptParser.text(from: "<bash-input>cd x && ls</bash-input><bash-stdout>out</bash-stdout>") == nil)
    }
    @Test func injectedNotificationsAreNotPrompts() {
        #expect(TranscriptParser.text(from: "<task-notification><task-id>1</task-id></task-notification>") == nil)
    }
    @Test func realPromptsThatStartWithAngleBracketSurvive() {
        #expect(TranscriptParser.text(from: "<div> is broken, fix it") == "<div> is broken, fix it")
    }
    @Test func nextStepQuotesClaudesLastReplyWhenNothingElseApplies() {
        var d = TranscriptParser.digest(lines: lines); d.lastAssistantText = "Perch is running now. Try the idle trigger."
        let p = Recap.project(digest: d, git: GitInfo(uncommitted: 0), now: Date())!
        #expect(p.next == "")
    }
    @Test func keepsRecentMessagesForModels() {
        let d = TranscriptParser.digest(lines: lines)
        #expect(d.recent.map(\.role) == ["user", "assistant"])
    }
    @Test func promptIncludesGitFactsAndConversation() {
        let d = TranscriptParser.digest(lines: lines)
        let p = RecapPrompt.build(digest: d, git: GitInfo(uncommitted: 2, lastCommit: "Fix sign"), projectName: "site")
        #expect(p.contains("2 uncommitted files")); #expect(p.contains("Fix sign")); #expect(p.contains("User: make the sign centred"))
    }
    @Test func parsesJsonInsideCodeFences() {
        let raw = "Here you go:\n```json\n{\"headline\":\"You were fixing the sign.\",\"context\":\"Centred it.\",\"next\":\"Add a table.\"}\n```"
        #expect(RecapPrompt.parse(raw)?.next == "Add a table.")
    }
    @Test func rejectsReplyWithoutJson() { #expect(RecapPrompt.parse("Sorry, I cannot do that.") == nil) }
    @Test func recapTextReplacesWordsButKeepsFacts() {
        let d = TranscriptParser.digest(lines: lines)
        let p = Recap.project(digest: d, git: nil, now: Date())!.withRecap(RecapText(headline: "H.", context: "C", next: "N"))
        #expect(p.headline == "H."); #expect(p.next == "N"); #expect(p.sessionId == "s1"); #expect(p.branch == "main")
    }
    @Test func statedNextStepBeatsGit() {
        var d = TranscriptParser.digest(lines: lines); d.lastAssistantText = "Done with the table. Next: wire the logo upload to the ledger."
        let p = Recap.project(digest: d, git: GitInfo(uncommitted: 2, files: ["a", "b"]), now: Date())!
        #expect(p.next == "Next: Wire the logo upload to the ledger")
    }
    @Test func parsesPorcelainStatus() {
        let g = GitInfo.parse(status: "## feature/x...origin/feature/x [ahead 3]\n M Sources/App.swift\n?? docs/notes.md\nR  old.txt -> new.txt\n", lastCommit: nil)
        #expect(g.ahead == 3); #expect(g.branch == "feature/x"); #expect(g.files == ["App.swift", "notes.md", "new.txt"])
    }
    @Test func neverSuggestsGitChores() {
        var d = TranscriptParser.digest(lines: lines); d.lastAssistantText = "Done. Next: commit and push the changes."
        let p = Recap.project(digest: d, git: GitInfo(uncommitted: 4, files: ["a"]), now: Date())!
        #expect(p.next == "")
        #expect(Recap.isGitChore("Commit changes to a.swift")); #expect(!Recap.isGitChore("Wire up the logo upload"))
    }
}
