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
    @Test func userSpokeLastAndNothingCameBackIsNotYourTurn() {
        var d = TranscriptParser.digest(lines: lines); d.lastRole = "user"; d.turnOpen = false
        let p = Recap.project(digest: d, git: nil, now: Date())!
        #expect(p.status.kind == "idle"); #expect(p.status.text == "Claude Code stopped before replying"); #expect(p.next == "")
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
        #expect(p.next == "Wire the logo upload to the ledger")
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
        #expect(Recap.isGitChore("Push the branch")); #expect(Recap.isGitChore("Open a PR for the fix")); #expect(Recap.isGitChore("Run git push"))
        #expect(!Recap.isGitChore("Add push notifications")); #expect(!Recap.isGitChore("Fix the commitment dialog")); #expect(!Recap.isGitChore("Handle merged cells"))
    }

    // MARK: what the agent is doing, from the shape of the transcript
    let prompt = #"{"type":"user","sessionId":"s2","cwd":"/Users/a/app","timestamp":"2026-10-07T09:00:00.000Z","message":{"content":"run the tests"}}"#
    func toolCall(_ name: String, _ input: String = "{}", id: String = "t1") -> String {
        #"{"type":"assistant","timestamp":"2026-10-07T09:00:05.000Z","message":{"stop_reason":"tool_use","content":[{"type":"tool_use","id":"\#(id)","name":"\#(name)","input":\#(input)}]}}"#
    }
    func result(_ id: String = "t1") -> String { #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"\#(id)","content":"ok"}]}}"# }
    func status(_ lines: [String], quiet: TimeInterval) -> (kind: String, text: String, next: String) {
        let p = Recap.project(digest: TranscriptParser.digest(lines: lines), git: nil, now: Date(), quietFor: quiet)!
        return (p.status.kind, p.status.text, p.next)
    }

    @Test func aToolCallWithoutAResultIsPending() {
        #expect(TranscriptParser.digest(lines: [prompt, toolCall("Edit")]).pendingTool?.name == "Edit")
        #expect(TranscriptParser.digest(lines: [prompt, toolCall("Edit"), result()]).pendingTool == nil)
    }
    @Test func aStaleToolCallIsWaitingForYourOK() {
        #expect(status([prompt, toolCall("Edit")], quiet: 5).kind == "running")
        let s = status([prompt, toolCall("Edit")], quiet: 90)
        #expect(s.kind == "attention"); #expect(s.text == "Claude is waiting for your OK")
    }
    @Test func aLongCommandIsWorkingUntilItsOwnTimeout() {
        let build = toolCall("Bash", #"{"command":"swift build","timeout":600000}"#)
        #expect(status([prompt, build], quiet: 400).kind == "running")
        #expect(status([prompt, build], quiet: 700).kind == "attention")
        #expect(status([prompt, toolCall("Bash")], quiet: 200).kind == "attention")   // default timeout is two minutes
    }
    @Test func aQuestionAskedThroughTheToolNeedsYouAtOnce() {
        let ask = toolCall("AskUserQuestion", #"{"questions":[{"question":"Which database should we use?"}]}"#)
        let s = status([prompt, ask], quiet: 1)
        #expect(s.kind == "attention"); #expect(s.next == "Answer: “Which database should we use?”")
        #expect(status([prompt, toolCall("ExitPlanMode")], quiet: 1).text == "Claude has a plan for you")
    }
    @Test func stoppingTheAgentIsNotYourTurn() {
        let stop = #"{"type":"user","message":{"content":[{"type":"text","text":"[Request interrupted by user]"}]}}"#
        let s = status([prompt, toolCall("Bash"), stop], quiet: 600)
        #expect(s.kind == "idle"); #expect(s.text == "You stopped Claude")
    }
    @Test func acknowledgementsAreNotWhatYouWereDoing() {
        let yes = #"{"type":"user","timestamp":"2026-10-07T09:10:00.000Z","message":{"content":"yes, push it please"}}"#
        let d = TranscriptParser.digest(lines: [prompt, yes])
        #expect(d.lastUserText == "yes, push it please"); #expect(d.lastAsk == "run the tests")
        #expect(Recap.project(digest: d, git: nil, now: Date())!.headline == "Run the tests.")
        #expect(Recap.isAcknowledgement("ok go ahead")); #expect(Recap.isAcknowledgement("LGTM!")); #expect(Recap.isAcknowledgement("\u{05DB}\u{05DF}"))
        #expect(!Recap.isAcknowledgement("yes but rename it first")); #expect(!Recap.isAcknowledgement("fix the login"))
    }
    @Test func readsHowTheSessionWasStarted() {
        let headless = #"{"type":"user","entrypoint":"sdk-cli","sessionId":"s3","cwd":"/x","message":{"content":"summarise"}}"#
        #expect(TranscriptParser.digest(lines: [headless]).entrypoint == "sdk-cli")
    }
}
