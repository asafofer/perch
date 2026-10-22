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
    @Test func aTurnThatSaysMoreThanOnceIsKeptWhole() {
        // an answer, then a stop hook speaks (meta) and the agent answers again: Preview shows both; your next message starts afresh
        let turn = [
            #"{"type":"user","message":{"content":"hi"}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"Hi! What can I help with?"}]}}"#,
            #"{"type":"user","isMeta":true,"message":{"content":"Stop hook feedback: ..."}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"Nothing to publish."}],"stop_reason":"end_turn"}}"#,
        ]
        #expect(TranscriptParser.digest(lines: turn).turnFull == "Hi! What can I help with?\n\nNothing to publish.")
        #expect(TranscriptParser.digest(lines: turn).lastAssistantFull == "Nothing to publish.")
        let next = turn + [#"{"type":"user","message":{"content":"thanks"}}"#, #"{"type":"assistant","message":{"content":[{"type":"text","text":"Any time."}]}}"#]
        #expect(TranscriptParser.digest(lines: next).turnFull == "Any time.")
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
    @Test func codexHeadlessRunsAreMarked() {
        func meta(_ extra: String) -> SessionDigest { CodexTranscript.digest(lines: [#"{"type":"session_meta","payload":{"id":"t1","cwd":"/Users/a/site","# + extra + "}}"]) }
        #expect(!meta(#""originator":"Codex Desktop","source":"vscode""#).headless)
        #expect(!meta(#""originator":"codex_cli_rs","source":"cli""#).headless)
        #expect(meta(#""originator":"codex_exec","source":"exec""#).headless)
        #expect(meta(#""originator":"Codex Desktop","source":{"subagent":{"thread_spawn":{}}}"#).headless)
        #expect(meta(#""originator":"Codex Desktop","source":"vscode""#).sessionId == "t1")
    }
    @Test func aWorktreeIsNamedByItsRepo() {
        #expect(Recap.folderName("/Users/a/Documents/perch/.claude/worktrees/wizardly-williams-42a0c0") == "perch")
        #expect(Recap.folderName("/Users/a/Documents/perch") == "perch")
        var d = TranscriptParser.digest(lines: lines)
        d.cwd = "/Users/a/Documents/perch/.claude/worktrees/wizardly-williams-42a0c0"
        #expect(Recap.project(digest: d, git: nil, now: Date())!.name == "perch")
    }
    @Test func sessionsWithoutAProjectAreNamedByTitle() {
        #expect(Recap.isFolderless("/Users/a/Library/Application Support/Claude/scratch-workspaces/x/y/scratch-2026-10-09-ab78ac"))
        #expect(Recap.isFolderless("/Users/a/Documents/Codex/2026-09-27/new-chat"))
        #expect(!Recap.isFolderless("/Users/a/Documents/Codex/perch"))
        #expect(!Recap.isFolderless("/Users/a/site"))
        var d = TranscriptParser.digest(lines: lines)
        d.cwd = "/Users/a/Documents/Codex/2026-09-27/new-chat"
        let p = Recap.project(digest: d, git: nil, now: Date())!
        #expect(p.name == "Fix the review sign"); #expect(p.topic == "")
        d.cwd = "/Users/a/site"
        let q = Recap.project(digest: d, git: nil, now: Date())!
        #expect(q.name == "site"); #expect(q.topic == "Fix the review sign")
    }
    @Test func oldNewsIsHistory() {
        let now = Date()
        // back from a weekend: everything since you left still counts
        let weekend = now.addingTimeInterval(-60 * 3600)
        #expect(WhileAway.newsSince(now: now, lastLeft: weekend) == weekend)
        // a short break, or no break known: the last day counts
        #expect(WhileAway.newsSince(now: now, lastLeft: now.addingTimeInterval(-3600)) == now.addingTimeInterval(-86_400))
        #expect(WhileAway.newsSince(now: now, lastLeft: nil) == now.addingTimeInterval(-86_400))
    }
    @Test func aQuestionFromDaysAgoNoLongerNeedsYou() {
        var d = TranscriptParser.digest(lines: lines)
        d.lastAssistantText = "What would you change first?"
        var p = Recap.project(digest: d, git: nil, now: Date())!
        #expect(p.needsAttention)
        let since = Date().addingTimeInterval(-86_400)
        p.lastActive = since.addingTimeInterval(-3600)
        let old = p.settled(since: since)
        #expect(!old.needsAttention); #expect(old.status.kind == "idle"); #expect(old.status.text == p.status.text)
        p.lastActive = since.addingTimeInterval(3600)
        #expect(p.settled(since: since).needsAttention)
        // a request still open is never history
        p.lastActive = since.addingTimeInterval(-3600)
        p.ask = Ask(id: "a", agent: "claude", tool: "Bash", input: ["command": "ls"])
        #expect(p.settled(since: since).needsAttention)
    }
    @Test func aQuestionYouSawAndLeftForAnotherSessionIsHistory() {
        var d = TranscriptParser.digest(lines: lines)
        d.lastAssistantText = "What broke, and where would you have wanted the red light?"
        let at = Date().addingTimeInterval(-18 * 3600)
        var asked = Recap.project(digest: d, git: nil, now: Date())!
        asked.lastActive = at
        var other = Recap.project(digest: TranscriptParser.digest(lines: lines.map { $0.replacingOccurrences(of: "\"s1\"", with: "\"s9\"") }), git: nil, now: Date())!
        other.lastActive = Date()
        #expect(asked.needsAttention); #expect(asked.id != other.id)
        let seenBoth = [asked.id: at.timeIntervalSince1970, other.id: Date().timeIntervalSince1970]
        // seen, then a later change seen in another session: you moved on
        let moved = Project.movedOn([asked, other], seen: seenBoth)
        #expect(!moved[0].needsAttention); #expect(moved[0].status.kind == "idle")
        // never seen: still yours to answer
        #expect(Project.movedOn([asked, other], seen: [other.id: Date().timeIntervalSince1970])[0].needsAttention)
        // seen, but nothing seen since in another session
        #expect(Project.movedOn([asked, other], seen: [asked.id: at.timeIntervalSince1970])[0].needsAttention)
        // a request a hook reports still open never settles
        asked.ask = Ask(id: "a", agent: "claude", tool: "Bash", input: ["command": "ls"])
        #expect(Project.movedOn([asked, other], seen: seenBoth)[0].needsAttention)
    }
    @Test func aSessionAtWorkKeepsTheQuestionYouLeftAsHistory() {
        var d = TranscriptParser.digest(lines: lines)
        d.lastAssistantText = "What broke, and where would you have wanted the red light?"
        let at = Date().addingTimeInterval(-3600)
        var asked = Recap.project(digest: d, git: nil, now: Date())!
        asked.lastActive = at
        var working = Recap.project(digest: TranscriptParser.digest(lines: lines.map { $0.replacingOccurrences(of: "\"s1\"", with: "\"s9\"") }), git: nil, now: Date())!
        let looked = Date().addingTimeInterval(-60)
        working.lastActive = looked
        let seen = [asked.id: at.timeIntervalSince1970, working.id: looked.timeIntervalSince1970]
        #expect(!Project.movedOn([asked, working], seen: Project.lastSeen([asked, working], seen: seen, fresh: { _ in false }))[0].needsAttention)
        // a tool call moves the session you are in past what you saw of it: what you saw still counts, so the question stays history
        working.lastActive = Date()
        let fresh: (Project) -> Bool = { $0.id == working.id }
        let mid = Project.lastSeen([asked, working], seen: seen, fresh: fresh)
        #expect(mid[working.id] == looked.timeIntervalSince1970)
        #expect(!Project.movedOn([asked, working], seen: mid)[0].needsAttention)
        // seen but not marked yet (in front of you in the Claude app): its last change counts
        #expect(Project.lastSeen([working], seen: [:], fresh: { _ in false })[working.id] == working.lastActive!.timeIntervalSince1970)
    }
    @Test func aNumberInASentenceIsNotAList() {
        #expect(Recap.outcome("My recommendation is to start with item 1. It's cheap and quick.") == "My recommendation is to start with item 1. It's cheap and quick.")
        #expect(Recap.outcome("Done.\n1. Fixed the hero spacing\n2. Cut the video") == "Fixed the hero spacing. Cut the video.")
    }
    @Test func whileWorkingTheCardSaysWhatItIsDoing() {
        let working = [
            #"{"type":"assistant","timestamp":"2026-10-07T08:00:00.000Z","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"I pushed main to the remote."}]}}"#,
            #"{"type":"user","sessionId":"s1","cwd":"/Users/a/site","timestamp":"2026-10-07T09:00:00.000Z","message":{"content":"fix the scan and add tests for it"}}"#,
            #"{"type":"assistant","timestamp":"2026-10-07T09:01:00.000Z","message":{"stop_reason":"tool_use","content":[{"type":"text","text":"Now checking the scanner tests."},{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"swift test --filter Scan\nmore","timeout":600000}}]}}"#,
        ]
        let d = TranscriptParser.digest(lines: working)
        #expect(d.step == "Running `swift test --filter Scan`")
        let p = Recap.project(digest: d, git: nil, now: Date(), quietFor: 5)!
        #expect(p.status.kind == "running")
        #expect(p.context == "Now checking the scanner tests.")
        #expect(p.now == "Running `swift test --filter Scan`")
        // once it is done, the outcome is back and there is no Now
        let done = TranscriptParser.digest(lines: working + [#"{"type":"user","timestamp":"2026-10-07T09:02:00.000Z","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]}}"#,
            #"{"type":"assistant","timestamp":"2026-10-07T09:03:00.000Z","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"The scan now finds every session."}]}}"#])
        let q = Recap.project(digest: done, git: nil, now: Date(), quietFor: 5)!
        #expect(q.context == "The scan now finds every session."); #expect(q.now == nil)
    }
    @Test func aNewPromptStartsTheActivityOver() {
        let d = TranscriptParser.digest(lines: [
            #"{"type":"assistant","message":{"stop_reason":"tool_use","content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"/x/app.js"}}]}}"#,
            #"{"type":"user","timestamp":"2026-10-07T09:00:00.000Z","message":{"content":"now the list please"}}"#,
        ])
        #expect(d.step == nil); #expect(d.narration == nil)
        let p = Recap.project(digest: { var x = d; x.cwd = "/Users/a/site"; return x }(), git: nil, now: Date(), quietFor: 5)!
        #expect(p.context == "You said: “now the list please”")
    }
    @Test func stepsReadAsWhatItIsDoing() {
        #expect(Activity.step(tool: "Edit", input: ["file_path": "/a/b/app.js"]) == "Editing app.js")
        #expect(Activity.step(tool: "Read", input: ["file_path": "/a/README.md"]) == "Reading README.md")
        #expect(Activity.step(tool: "Grep", input: ["pattern": "isFresh"]) == "Searching for “isFresh”")
        #expect(Activity.step(tool: "WebFetch", input: ["url": "https://raycast.com/x"]) == "Reading raycast.com")
        #expect(Activity.step(tool: "exec_command", input: ["command": ["bash", "-lc", "npm test"]]) == "Running `npm test`")
        #expect(Activity.step(tool: "Bash", input: ["command": "x", "description": "Check how the list selection is set on open"]) == "Checking how the list selection is set on open")
        let said = ["Run the tests", "Make a build", "Stop the server", "Grep for it", "Commit the fix", "Verify it", "Open the app", "Write a test", "See logs", "Fix it", "Show status", "Git status", "npm test", "Reading it", "Re-run it"]
        #expect(said.map(Activity.ongoing) == ["Running the tests", "Making a build", "Stopping the server", "Grepping for it", "Committing the fix", "Verifying it",
                                               "Opening the app", "Writing a test", "Seeing logs", "Fixing it", "Showing status", "Git status", "npm test", "Reading it", "Re-run it"])
        #expect(Activity.step(tool: "Bash", input: ["command": "S=/tmp/x; swift test", "description": "Run the test suite"]) == "Running the test suite")
        #expect(Activity.step(tool: "mcp__linear__save_issue", input: [:]) == "Using issue")
        #expect(Activity.step(tool: "TodoWrite", input: [:]) == nil)
    }
    @Test func aCodexPromptStartingWithATagStartsANewTurn() {
        let msg = { (role: String, text: String) in #"{"type":"response_item","payload":{"type":"message","role":""# + role + #"","content":[{"type":""# + (role == "user" ? "input_text" : "output_text") + #"","text":""# + text + #""}]}}"# }
        let turn = [msg("user", "fix the hero"), msg("assistant", "Fixed."), msg("user", "<hook_prompt hook_run_id=\"1\">Check the tests.</hook_prompt>"), msg("assistant", "Tests pass.")]
        // what Codex adds itself goes on with the turn; your own prompt, even one that starts with a tag, starts a new one
        #expect(CodexTranscript.digest(lines: turn).turnFull == "Fixed.\n\nTests pass.")
        #expect(CodexTranscript.digest(lines: turn + [msg("user", "<div> is broken"), msg("assistant", "It lacks a width.")]).turnFull == "It lacks a width.")
    }
    @Test func codexStepsAndNarration() {
        let d = CodexTranscript.digest(lines: [
            #"{"timestamp":"2026-10-07T09:00:00Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"rewrite the install guide"}]}}"#,
            #"{"timestamp":"2026-10-07T09:00:05Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Reading the current guide first."}]}}"#,
            #"{"timestamp":"2026-10-07T09:00:06Z","type":"response_item","payload":{"type":"function_call","name":"shell","arguments":"{\"command\":[\"bash\",\"-lc\",\"cat docs/install.md\"]}"}}"#,
        ])
        #expect(d.step == "Running `cat docs/install.md`"); #expect(d.narration == "Reading the current guide first.")
    }
    @Test func typingNarrowsTheList() {
        let list = FakeSessionProvider().parkedProjects()
        #expect(ListFilter.shown(list, "") == [0, 1, 2, 3, 4, 5])
        #expect(ListFilter.shown(list, "web") == [1])
        #expect(ListFilter.shown(list, "INSTALL gui") == [2])
        #expect(ListFilter.shown(list, "fin sept") == [3])
        #expect(ListFilter.shown(list, "nothing like this").isEmpty)
    }
    @Test func theListGoesBySectionThenNewest() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = ISO8601DateFormatter().date(from: "2026-10-09T15:00:00Z")!
        func p(_ id: String, _ ago: TimeInterval, needs: Bool = false) -> Project {
            var x = Project(id: id, name: id, branch: nil, away: "", at: "", headline: "", context: "", next: "", topic: "", app: "claude",
                            agents: [AgentStatus(kind: needs ? .needsYou : .idle, text: "", app: "claude")], steps: [])
            x.lastActive = now.addingTimeInterval(-ago); return x
        }
        // yesterday, an hour ago, asking since this morning, a minute ago
        let list = [p("old", 20 * 3600), p("hour", 3600), p("asks", 6 * 3600, needs: true), p("now", 60)]
        #expect(ListFilter.ordered(list, "", now: now, calendar: cal) == [2, 3, 1, 0])
        #expect(list.map { ListFilter.section($0, now: now, calendar: cal) } == [.earlier, .today, .needsYou, .today])
    }
    @Test func sessionsAtWorkKeepTheirPlaces() {
        let now = Date()
        func p(_ id: String, _ ago: TimeInterval, began: TimeInterval, kind: AgentStatus.Kind) -> Project {
            var x = Project(id: id, name: id, branch: nil, away: "", at: "", headline: "", context: "", next: "", topic: "", app: "claude",
                            agents: [AgentStatus(kind: kind, text: "", app: "claude")], steps: [])
            x.lastActive = now.addingTimeInterval(-ago); x.startedAt = now.addingTimeInterval(-began); return x
        }
        // two at work, each writing a moment after the other, and one that finished a second ago
        var list = [p("done", 1, began: 100, kind: .done), p("a", 5, began: 3600, kind: .running), p("b", 2, began: 600, kind: .running)]
        #expect(ListFilter.ordered(list, "", now: now) == [2, 1, 0])
        list[1].lastActive = now
        #expect(ListFilter.ordered(list, "", now: now) == [2, 1, 0])
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
    @Test func keepsRecentMessages() {
        let d = TranscriptParser.digest(lines: lines)
        #expect(d.recent.map(\.role) == ["user", "assistant"])
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
    @Test func aTerminalSessionNoProcessRunsAsksNothing() throws {
        // Killed while its Bash call waited for your OK, resumed and closed without a word: the transcript still ends on that call.
        var p = try #require(Recap.project(digest: TranscriptParser.digest(lines: [prompt, toolCall("Bash", #"{"command":"npm run build"}"#)]), git: nil, now: Date(), quietFor: 900))
        p.terminal = true
        #expect(p.toolOpen)
        p.pid = 4242
        #expect(p.agentGone().status.kind == "attention")   // still running there: it waits for you
        p.pid = nil
        #expect(p.agentGone().status.kind == "idle"); #expect(p.agentGone().status.text == "Claude Code stopped mid-task")
        // Killed a moment ago, its call still within its time: not at work either.
        var fresh = try #require(Recap.project(digest: TranscriptParser.digest(lines: [prompt, toolCall("Bash", #"{"command":"npm run build"}"#)]), git: nil, now: Date(), quietFor: 5))
        fresh.terminal = true
        #expect(fresh.status.kind == "running"); #expect(fresh.agentGone().status.kind == "idle")
        fresh.pid = 4242
        #expect(fresh.agentGone().status.kind == "running")
        // What its hook said goes too, so resuming it later does not bring the request back.
        var live = LiveStatus.apply(HookEvent(agent: "claude", sessionId: "s2", kind: .asks({ var a = Ask(id: "r", agent: "claude", tool: "Bash", input: ["command": "npm run build"]); a.answerable = false; return a }())), to: nil)
        #expect(live.agentGone() == nil)
        let asked = p.applying(live)
        #expect(asked.agentGone().status.kind == "idle"); #expect(asked.agentGone().ask == nil)
        // A request held by its hook (OpenCode's) is settled by that hook, not by this.
        live = LiveStatus.apply(HookEvent(agent: "opencode", sessionId: "s2", kind: .asks(Ask(id: "o", agent: "opencode", tool: "bash", input: ["command": "ls"]))), to: nil)
        #expect(live.agentGone()?.asks.map(\.id) == ["o"])
        // An app session is never a terminal one: nothing changes.
        p.terminal = false
        #expect(p.agentGone().status.kind == "attention")
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
        #expect(s.kind == "attention"); #expect(s.text == "Claude asked you something"); #expect(s.next == "")   // the question is the card, not a Next row
        #expect(status([prompt, toolCall("ExitPlanMode")], quiet: 1).text == "Claude has a plan for you")
    }
    static let twoQuestions = #"{"questions":[{"question":"What should an external screen show at rest?","header":"External","multiSelect":false,"options":[{"label":"Nothing at rest (Recommended)","description":"No virtual notch."},{"label":"Built-in screen only","description":"Never on external screens."}]},{"question":"How should hovering the top edge behave?","header":"Hover","multiSelect":false,"options":[{"label":"No hover open","description":"Hotkey only."},{"label":"Hover opens"}]}]}"#
    @Test func aQuestionOpenInTheTranscriptIsAQuestionWithItsChoicesAndNeverAnswerable() throws {
        let p = Recap.project(digest: TranscriptParser.digest(lines: [prompt, toolCall("AskUserQuestion", Self.twoQuestions)]), git: nil, now: Date(), quietFor: 1)!
        let a = try #require(p.ask)
        #expect(a.kind == .question); #expect(a.title == "Claude asked you something"); #expect(!a.answerable)
        #expect(a.questions.map(\.text) == ["What should an external screen show at rest?", "How should hovering the top edge behave?"])
        #expect(a.questions[0].options == ["Nothing at rest (Recommended)", "Built-in screen only"]); #expect(a.questions[0].notes == ["No virtual notch.", "Never on external screens."])
        #expect(a.questions[1].notes == ["Hotkey only.", ""])
        #expect(a.subject == "What should an external screen show at rest?"); #expect(a.transcriptAt != nil)
        #expect(p.next == ""); #expect(p.status.text == "Claude asked you something")
    }
    @Test func aQuestionTheToolHasAlreadyHadAnAnswerToIsNotOpen() {
        let p = Recap.project(digest: TranscriptParser.digest(lines: [prompt, toolCall("AskUserQuestion", Self.twoQuestions), result()]), git: nil, now: Date(), quietFor: 1)!
        #expect(p.ask == nil)
    }
    @Test func aQuestionAsFreeTextInTheReplyIsNotAnAsk() {
        let d = TranscriptParser.digest(lines: [prompt, #"{"type":"assistant","timestamp":"2026-10-07T09:00:05.000Z","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"Which database should we use?"}]}}"#])
        #expect(Recap.project(digest: d, git: nil, now: Date(), quietFor: 400)!.ask == nil)
    }
    @Test func aQuestionFromTheTranscriptGrowsOldAndIsHistory() {
        let p = Recap.project(digest: TranscriptParser.digest(lines: [prompt, toolCall("AskUserQuestion", Self.twoQuestions)]), git: nil, now: Date(), quietFor: 1)!
        let settled = p.settled(since: Date())
        #expect(settled.ask == nil); #expect(!settled.needsAttention)
    }
    @Test func stoppingTheAgentIsNotYourTurn() {
        let stop = #"{"type":"user","message":{"content":[{"type":"text","text":"[Request interrupted by user]"}]}}"#
        let s = status([prompt, toolCall("Bash"), stop], quiet: 600)
        #expect(s.kind == "idle"); #expect(s.text == "You stopped Claude")
    }

    // MARK: work left running in the background (the shapes Claude Code 2.1 writes)
    func launched(_ id: String = "t1", _ result: String) -> String {
        #"{"type":"user","timestamp":"2026-10-07T09:00:06.000Z","message":{"content":[{"type":"tool_result","tool_use_id":"\#(id)","content":"Async agent launched successfully."}]},"toolUseResult":\#(result)}"#
    }
    let turnOver = #"{"type":"assistant","timestamp":"2026-10-07T09:00:09.000Z","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"I started helpers for M4, M5 and M8. I'll pick up when they report."}]}}"#
    func notification(_ taskId: String, call: String? = nil, status: String? = "completed") -> String {
        let note = "<task-notification>\n<task-id>\(taskId)</task-id>\n" + (call.map { "<tool-use-id>\($0)</tool-use-id>\n" } ?? "")
            + (status.map { "<status>\($0)</status>\n" } ?? "<event>first</event>\n") + "<summary>It ended</summary>\n</task-notification>"
        return String(data: try! JSONSerialization.data(withJSONObject: ["type": "queue-operation", "operation": "enqueue", "content": note]), encoding: .utf8)!
    }
    func helper(_ id: String, _ about: String) -> [String] {
        [toolCall("Agent", #"{"description":"\#(about)","prompt":"go","run_in_background":true}"#, id: id),
         launched(id, #"{"isAsync":true,"status":"async_launched","agentId":"a-\#(id)","description":"\#(about)"}"#)]
    }
    /// The session `after` seconds past the launch, its transcript still for most of that.
    func later(_ lines: [String], _ after: TimeInterval = 300) -> Project {
        let launch = ISO8601DateFormatter().date(from: "2026-10-07T09:00:06Z")!
        return Recap.project(digest: TranscriptParser.digest(lines: lines), git: nil, now: launch.addingTimeInterval(after), quietFor: after - 3)!
    }

    @Test func helpersLeftInTheBackgroundAreWorkUntilTheyReportBack() {
        let three = [prompt] + helper("t1", "M4") + helper("t2", "M5") + helper("t3", "M8") + [turnOver]
        let d = TranscriptParser.digest(lines: three)
        #expect(!d.turnOpen); #expect(d.background.map(\.taskId) == ["a-t1", "a-t2", "a-t3"])
        let p = later(three)
        #expect(p.status.kind == "running"); #expect(p.waiting); #expect(p.now == "Waiting on 3 helpers")
        #expect(p.context == "I started helpers for M4, M5 and M8.")   // what it said it is doing, not old news
        // Two report back (by their tool call, or by their task id): one is still out.
        let two = three + [notification("a-t1", call: "t1"), notification("a-t2")]
        #expect(later(two).now == "Waiting on a helper: M8")
        // The last one reports: the agent's turn goes on, and its end is the finish.
        let all = two + [notification("a-t3", call: "t3"), #"{"type":"user","origin":{"kind":"task-notification"},"message":{"content":"<task-notification>\n<task-id>a-t3</task-id>\n<status>completed</status>\n</task-notification>"}}"#]
        #expect(TranscriptParser.digest(lines: all).turnOpen)
        let done = all + [#"{"type":"assistant","timestamp":"2026-10-07T09:20:00.000Z","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"All three milestones are in."}]}}"#]
        let q = later(done, 1300)
        #expect(q.status.kind == "done"); #expect(!q.waiting); #expect(q.now == nil)
        // Gone without a word (the app quit with them out): half an hour on, with no sign of life, it is not at work.
        #expect(later(three, 2000).status.kind == "done")
        // A helper writing its own transcript is a sign of life (the scan reads it, `SessionScanner.heardFrom`).
        var alive = TranscriptParser.digest(lines: three)
        alive.background[0].at = ISO8601DateFormatter().date(from: "2026-10-07T09:30:00Z")
        let launch = ISO8601DateFormatter().date(from: "2026-10-07T09:00:06Z")!
        let still = Recap.project(digest: alive, git: nil, now: launch.addingTimeInterval(2000), quietFor: 1990)!
        #expect(still.status.kind == "running"); #expect(still.now == "Waiting on a helper: M4")
    }
    @Test func aHelperWaitingOnItsOwnBackgroundWorkIsStillOut() {
        // Claude Code 2.1: a helper that put its own command in the background stops, and says so; it reports again when
        // that is over, with no tool call id the second time.
        func queued(_ content: String) -> String {
            String(data: try! JSONSerialization.data(withJSONObject: ["type": "queue-operation", "operation": "enqueue", "content": content]), encoding: .utf8)!
        }
        let interim = queued("<task-notification>\n<task-id>a-t1</task-id>\n<tool-use-id>t1</tool-use-id>\n<status>completed</status>\n<summary>Agent \"M4\" is waiting on its own background work</summary>\n<note>This agent stopped with background work of its own still running. It may resume on its own when that work completes or reports, and the same task-id notifies again if it does; the result below may be interim.</note>\n<result>The 90-second sleep is running in the background.</result>\n</task-notification>")
        let final = queued("<task-notification>\n<task-id>a-t1</task-id>\n<status>completed</status>\n<summary>Agent \"M4\" finished</summary>\n<note>A task-notification fires each time this agent stops with no live background children of its own.</note>\n<result>done</result>\n</task-notification>")
        let out = [prompt] + helper("t1", "M4") + [turnOver, interim]
        #expect(later(out).status.kind == "running"); #expect(later(out).now == "Waiting on a helper: M4")
        #expect(later(out + [final]).status.kind == "done")
    }
    @Test func aCommandLeftInTheBackgroundIsWorkButAServerIsNot() {
        let ci = toolCall("Bash", #"{"command":"gh pr checks 12 --watch","description":"Wait for the PR checks","run_in_background":true}"#)
        let started = launched("t1", #"{"stdout":"","stderr":"","interrupted":false,"backgroundTaskId":"b1"}"#)
        let p = later([prompt, ci, started, turnOver])
        #expect(p.status.kind == "running"); #expect(p.now == "Waiting for the PR checks")
        #expect(later([prompt, ci, started, turnOver, notification("b1", call: "t1")]).status.kind == "done")
        // Half an hour from its start it no longer counts, whatever came since: a session picked up again is not held by it.
        #expect(later([prompt, ci, started, turnOver], 2000).status.kind == "done")
        // A dev server runs until it is stopped: nothing waits on it, so the turn's end is the finish.
        let server = toolCall("Bash", #"{"command":"cd ui && python3 -m http.server 8765","run_in_background":true}"#)
        #expect(later([prompt, server, started, turnOver], 30).status.kind == "done")
        for c in ["npm run dev", "pnpm --filter web dev", "yarn dev:web", "npx vite --port 3000", "next dev", "rails s", "tail -f log/dev.log", "docker compose up"] {
            #expect(Background.neverEnds(c), "\(c)")
        }
        for c in ["gh pr checks 12 --watch", "gh run watch 123", "sleep 300 > /dev/null; gh pr checks 12", "npm run build", "npx vite build", "swift test", "docker compose up -d"] {
            #expect(!Background.neverEnds(c), "\(c)")
        }
    }
    @Test func aWatchGoesOnThroughItsEventsAndEndsWithItsStatusOrDeadline() {
        let watch = toolCall("Monitor", #"{"command":"gh pr checks 12","description":"CI checks on PR 12","timeout_ms":600000}"#)
        let started = launched("t1", #"{"taskId":"m1","timeoutMs":600000,"persistent":false}"#)
        let lines = [prompt, watch, started, turnOver, notification("m1", status: nil)]
        #expect(later(lines).now == "Watching CI checks on PR 12")
        #expect(later(lines + [notification("m1", call: "t1")]).status.kind == "done")
        #expect(later(lines, 700).status.kind == "done")   // past its own deadline
    }
    @Test func whatTheAgentStopsIsOver() {
        let lines = [prompt] + helper("t1", "M4") + [turnOver]
        #expect(later(lines).status.kind == "running")
        #expect(later(lines + [toolCall("TaskStop", #"{"task_id":"a-t1"}"#, id: "t9"), result("t9"), turnOver]).status.kind == "done")
        // A helper that ran in the foreground was waited on within the turn: its end is the turn's.
        let foreground = [prompt, toolCall("Agent", #"{"description":"M4","prompt":"go"}"#), launched("t1", #"{"status":"completed","agentId":"a1"}"#), turnOver]
        #expect(TranscriptParser.digest(lines: foreground).background.isEmpty)
    }
    @Test func acknowledgementsAreNotWhatYouWereDoing() {
        let yes = #"{"type":"user","timestamp":"2026-10-07T09:10:00.000Z","message":{"content":"yes, push it please"}}"#
        let d = TranscriptParser.digest(lines: [prompt, yes])
        #expect(d.lastUserText == "yes, push it please"); #expect(d.lastAsk == "run the tests")
        #expect(Recap.project(digest: d, git: nil, now: Date())!.headline == "Run the tests.")
        #expect(Recap.isAcknowledgement("ok go ahead")); #expect(Recap.isAcknowledgement("LGTM!")); #expect(Recap.isAcknowledgement("\u{05DB}\u{05DF}"))
        #expect(!Recap.isAcknowledgement("yes but rename it first")); #expect(!Recap.isAcknowledgement("fix the login"))
    }
    @Test func theTopLineSaysWhatHappenedWhileYouWereAway() {
        let now = Date(), left = now.addingTimeInterval(-3600)
        let line = { (kind: String, ago: TimeInterval, fresh: Bool, away: Date?) in
            WhileAway.line(kind: kind, lastActive: now.addingTimeInterval(-ago), now: now, awaySince: away, fresh: fresh)
        }
        #expect(line("done", 2880, true, left) == "Finished 12m after you left")
        #expect(line("done", 3570, true, left) == "Finished just after you left")
        #expect(line("attention", 2400, true, left) == "Waiting on you for 40m")
        #expect(line("idle", 1800, true, left) == "Stopped 30m after you left")
        #expect(line("running", 10, true, left) == "Working now")
        // Before you left, or no break to measure against: plain age, and "Finished" only while it is news.
        #expect(line("done", 7200, true, left) == "Finished 2h ago")
        #expect(line("done", 7200, false, left) == "2h ago")
        #expect(line("done", 64_800, false, nil) == "18h ago")
        #expect(line("attention", 600, false, nil) == "Waiting on you for 10m")
    }
    // MARK: the card says what the agent did, not what you typed
    @Test func contextIsTheAgentsOutcome() {
        var d = TranscriptParser.digest(lines: lines)
        d.lastAssistantText = "Done. Settings now fits the panel: the title moved into the top strip. Want me to rebuild?"
        d.lastAssistantFull = d.lastAssistantText
        let p = Recap.project(digest: d, git: nil, now: Date())!
        #expect(p.context == "Settings now fits the panel: the title moved into the top strip.")
    }
    @Test func outcomeSkipsFillerMarkdownAndListLeadIns() {
        #expect(Recap.outcome("Sure! ## Summary - Fixed the clipping on small windows. - Added a test.") == "Fixed the clipping on small windows. Added a test.")
        #expect(Recap.outcome("Here is what changed:") == nil)
        #expect(Recap.outcome("Done.") == nil)
        #expect(Recap.outcome("**Build passes** and the three flaky tests are gone.") == "Build passes and the three flaky tests are gone.")
    }
    @Test func withNoOutcomeTheCardFallsBackToYourAsk() {
        let p = Recap.project(digest: TranscriptParser.digest(lines: lines), git: nil, now: Date())!   // "Done. Want a table next?"
        #expect(p.context == "You said: “make the sign centred”")
    }
    @Test func theAgentNarratingItsOwnPlanIsNotYourNextStep() {
        var d = TranscriptParser.digest(lines: lines)
        d.lastAssistantText = "The summary screen works. Then run the design scanner over the changed code:"
        #expect(Recap.project(digest: d, git: nil, now: Date())!.next == "")
        d.lastAssistantText = "All wired up. Next: I'll clean up the CSS."
        #expect(Recap.project(digest: d, git: nil, now: Date())!.next == "")
        d.lastAssistantText = "All wired up. Next step: check the hero at phone width."
        #expect(Recap.project(digest: d, git: nil, now: Date())!.next == "Check the hero at phone width")
    }
    @Test func aHelloIsNotASessionWorthGoingBackTo() {
        var d = SessionDigest(); d.recent = [.init(role: "user", text: "nothin much"), .init(role: "assistant", text: "Not much here either. What should we build?")]
        #expect(Recap.isTrivial(d))
        d.recent = ["hey", "Hey!", "how are you", "Doing well, thanks.", "doing fine", "Glad to hear it.", "nothin much", "Fair enough.", "yep", "Okay"]
            .enumerated().map { .init(role: $0.offset % 2 == 0 ? "user" : "assistant", text: $0.element) }
        #expect(Recap.isTrivial(d))
        d.recent = [.init(role: "user", text: "fix the tests"), .init(role: "assistant", text: "Fixed the flaky login test.")]; d.didWork = true
        #expect(!Recap.isTrivial(d))   // short words, real work
        d.didWork = false
        d.recent = [.init(role: "user", text: "hi")]; d.turnOpen = true
        #expect(!Recap.isTrivial(d))   // still working: it may become something
    }
    @Test func readsHowTheSessionWasStarted() {
        let headless = #"{"type":"user","entrypoint":"sdk-cli","sessionId":"s3","cwd":"/x","message":{"content":"summarise"}}"#
        #expect(TranscriptParser.digest(lines: [headless]).entrypoint == "sdk-cli")
    }
}
