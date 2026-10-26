import Testing
import Foundation
@testable import PerchCore

private func json(_ o: Any) -> Data { try! JSONSerialization.data(withJSONObject: o) }
private let url = "https://github.com/asafofer/perch/pull/114"

/// What `gh pr view --json …` prints for a pull request with these parts.
private func view(state: String = "OPEN", draft: Bool = false, review: String = "", mergeable: String = "MERGEABLE", merge: String = "CLEAN",
                  rollup: [[String: Any]] = [], title: String = "Add a thing") -> Data {
    json(["number": 114, "title": title, "url": url, "state": state, "isDraft": draft, "reviewDecision": review,
          "mergeable": mergeable, "mergeStateStatus": merge, "statusCheckRollup": rollup] as [String: Any])
}
private func run(_ name: String, _ status: String, _ conclusion: String) -> [String: Any] {
    ["__typename": "CheckRun", "name": name, "status": status, "conclusion": conclusion]
}

@Suite struct PullRequestsTests {
    // MARK: the Claude app's list
    @Test func theAppsListBecomesPullRequests() {
        let prs = PullRequests.fromApp([
            ["prNumber": 70, "url": "https://github.com/asafofer/perch/pull/70", "repo": "asafofer/perch", "state": "MERGED", "own": true],
            ["prNumber": 99, "url": "https://github.com/asafofer/perch/pull/99", "repo": "asafofer/perch", "state": "OPEN", "own": true],
        ])
        #expect(prs.map(\.number) == [70, 99])
        #expect(prs.map(\.state) == [.merged, .open])
        #expect(prs[0].repo == "asafofer/perch")
    }

    @Test func aPullRequestTheAppSaysIsNotTheSessionsOwnIsLeftOut() {
        let prs = PullRequests.fromApp([
            ["prNumber": 1, "url": "https://github.com/a/b/pull/1", "repo": "a/b", "state": "OPEN", "own": false],
            ["prNumber": 2, "url": "https://github.com/a/b/pull/2", "repo": "a/b", "state": "OPEN", "branch": "w"],   // an older app does not say: its branch does
        ], sessionBranches: ["w"])
        #expect(prs.map(\.number) == [2])
    }

    @Test func aPullRequestTheSessionOnlyReadIsNotItsOwn() {
        let mine: [String: Any] = ["prNumber": 1, "url": "https://github.com/a/b/pull/1", "state": "OPEN", "branch": "claude/work"]
        let read: [String: Any] = ["prNumber": 2, "url": "https://github.com/a/b/pull/2", "state": "OPEN", "branch": "someone/else"]
        let said: [String: Any] = ["prNumber": 3, "url": "https://github.com/a/b/pull/3", "state": "MERGED", "branch": "x", "own": true]
        let no: [String: Any] = ["prNumber": 4, "url": "https://github.com/a/b/pull/4", "state": "MERGED", "branch": "claude/work", "own": false]
        #expect(PullRequests.fromApp([mine, read, said, no], sessionBranches: ["claude/work"]).map(\.number) == [1, 3])
        #expect(PullRequests.fromApp([mine, read], sessionBranches: []).isEmpty)
    }

    @Test func onlyGitHubAddressesAreKept() {
        let prs = PullRequests.fromApp([
            ["prNumber": 1, "url": "http://github.com/a/b/pull/1", "state": "OPEN", "own": true],
            ["prNumber": 2, "url": "https://evil.example/a/b/pull/2", "state": "OPEN", "own": true],
            ["prNumber": 3, "url": "https://github.com/a/b/pull/3", "state": "OPEN", "own": true],
        ])
        #expect(prs.map(\.number) == [3])
        #expect(PullRequests.fromApp("nonsense").isEmpty)
        #expect(PullRequests.fromApp(nil).isEmpty)
    }

    @Test func theSamePullRequestListedTwiceShowsOnce() {
        let e: [String: Any] = ["prNumber": 5, "url": "https://github.com/a/b/pull/5", "state": "MERGED", "own": true]
        #expect(PullRequests.fromApp([e, e]).count == 1)
    }

    // MARK: what a session shows
    @Test func nothingShowsWhenOff() {
        let pr = PullRequest(number: 1, repo: "a/b", url: "https://github.com/a/b/pull/1", state: .merged)
        #expect(PullRequests.visible([pr], mode: .off, idle: 0).isEmpty)
    }

    @Test func anOpenOneFromAnOldSessionIsNotTrustedButAMergedOneIs() {
        let open = PullRequest(number: 1, repo: "a/b", url: "https://github.com/a/b/pull/1", state: .open)
        let merged = PullRequest(number: 2, repo: "a/b", url: "https://github.com/a/b/pull/2", state: .merged)
        let old = PullRequests.staleAfter + 3600
        #expect(PullRequests.visible([open, merged], mode: .marks, idle: old).map(\.number) == [2])
        #expect(PullRequests.visible([open, merged], mode: .marks, idle: 3600).map(\.number) == [1, 2])
        // GitHub itself was asked: its answer stands, however old the session.
        #expect(PullRequests.visible([open, merged], mode: .checks, idle: old, verified: [open.url]).map(\.number) == [1, 2])
    }

    @Test func theMarkIsTheOneThatMattersMost() {
        let mk = { (n: Int, s: PullRequest.State, c: PullRequest.Checks?) in PullRequest(number: n, repo: "a/b", url: "https://github.com/a/b/pull/\(n)", state: s, checks: c) }
        #expect(PullRequests.top([mk(1, .merged, nil), mk(2, .open, .pass)])?.number == 2)
        #expect(PullRequests.top([mk(1, .open, .pass), mk(2, .open, .fail)])?.number == 2)
        #expect(PullRequests.top([mk(1, .closed, nil), mk(2, .merged, nil)])?.number == 2)
        #expect(PullRequests.top([]) == nil)
    }

    // MARK: gh's answer
    @Test func anOpenPullRequestWithGreenChecksPasses() {
        let pr = GitHubCLI.parse(view(review: "APPROVED", rollup: [run("ci", "COMPLETED", "SUCCESS"), run("lint", "COMPLETED", "SKIPPED")]), url: url)!
        #expect(pr.state == .open); #expect(pr.checks == .pass); #expect(pr.review == .approved); #expect(!pr.needsYou)
        #expect(pr.title == "Add a thing"); #expect(pr.repo == "asafofer/perch")
    }

    @Test func aFailingRequiredCheckNeedsYou() {
        let pr = GitHubCLI.parse(view(merge: "BLOCKED", rollup: [run("ci", "COMPLETED", "FAILURE"), run("lint", "COMPLETED", "SUCCESS")]), url: url)!
        #expect(pr.checks == .fail); #expect(pr.needsYou); #expect(pr.needsWords == "Checks failing on #114")
    }

    @Test func aFailingCheckCountsEvenWhenGitHubCallsItUnstable() {
        // UNSTABLE is what GitHub says both for an optional check failing and for any failure in a repository that requires none.
        let pr = GitHubCLI.parse(view(merge: "UNSTABLE", rollup: [run("ci", "COMPLETED", "FAILURE")]), url: url)!
        #expect(pr.checks == .fail); #expect(pr.needsYou)
    }

    @Test func checksStillRunningAreRunning() {
        let pr = GitHubCLI.parse(view(rollup: [run("ci", "IN_PROGRESS", ""), run("lint", "COMPLETED", "SUCCESS")]), url: url)!
        #expect(pr.checks == .running); #expect(!pr.needsYou)
    }

    @Test func aCheckThatRanTwiceStandsOnItsNewestRun() {
        // The first run failed, the re-run passed: it passes. Listed the other way round, it fails.
        func twice(_ first: String, _ second: String) -> PullRequest {
            GitHubCLI.parse(view(rollup: [
                ["__typename": "CheckRun", "name": "ci", "workflowName": "Tests", "status": "COMPLETED", "conclusion": first, "startedAt": "2026-10-26T12:00:00Z", "completedAt": "2026-10-26T12:05:00Z"],
                ["__typename": "CheckRun", "name": "ci", "workflowName": "Tests", "status": "COMPLETED", "conclusion": second, "startedAt": "2026-10-26T13:00:00Z", "completedAt": "2026-10-26T13:05:00Z"],
            ]), url: url)!
        }
        #expect(twice("FAILURE", "SUCCESS").checks == .pass)
        #expect(twice("SUCCESS", "FAILURE").checks == .fail)
        // Two checks with the same name in different workflows are two checks.
        let two = GitHubCLI.parse(view(merge: "BLOCKED", rollup: [
            ["__typename": "CheckRun", "name": "test", "workflowName": "A", "status": "COMPLETED", "conclusion": "FAILURE", "completedAt": "2026-10-26T12:00:00Z"],
            ["__typename": "CheckRun", "name": "test", "workflowName": "B", "status": "COMPLETED", "conclusion": "SUCCESS", "completedAt": "2026-10-26T13:00:00Z"],
        ]), url: url)!
        #expect(two.checks == .fail)
    }

    @Test func aCommitStatusCountsToo() {
        let failing = GitHubCLI.parse(view(merge: "BLOCKED", rollup: [["__typename": "StatusContext", "context": "ci/circle", "state": "FAILURE"]]), url: url)!
        let pending = GitHubCLI.parse(view(rollup: [["__typename": "StatusContext", "context": "ci/circle", "state": "PENDING"]]), url: url)!
        #expect(failing.checks == .fail); #expect(pending.checks == .running)
    }

    @Test func aReviewAskingForChangesAndAConflictNeedYou() {
        let changes = GitHubCLI.parse(view(review: "CHANGES_REQUESTED"), url: url)!
        let conflict = GitHubCLI.parse(view(mergeable: "CONFLICTING", merge: "DIRTY"), url: url)!
        #expect(changes.needsYou); #expect(changes.needsWords == "Changes requested on #114")
        #expect(conflict.conflict); #expect(conflict.needsYou); #expect(conflict.needsWords == "Merge conflicts on #114")
    }

    @Test func aMergedOrClosedOneNeedsNothingWhateverItsChecksSaid() {
        let merged = GitHubCLI.parse(view(state: "MERGED", review: "CHANGES_REQUESTED", mergeable: "CONFLICTING", rollup: [run("ci", "COMPLETED", "FAILURE")]), url: url)!
        let closed = GitHubCLI.parse(view(state: "CLOSED"), url: url)!
        #expect(merged.state == .merged); #expect(!merged.needsYou); #expect(merged.checks == nil)
        #expect(closed.state == .closed); #expect(!closed.needsYou)
    }

    @Test func aDraftIsADraft() {
        #expect(GitHubCLI.parse(view(draft: true), url: url)?.state == .draft)
    }

    @Test func garbageIsNotAPullRequest() {
        #expect(GitHubCLI.parse(Data("not json".utf8), url: url) == nil)
        #expect(GitHubCLI.parse(json(["title": "x"]), url: url) == nil)
    }

    // MARK: running gh
    @Test func theAddressIsHandedOverAfterTheOptionsSoItIsNeverAFlag() {
        let seen = Box<[String]>([])
        let cli = GitHubCLI(run: { args in seen.value = args; return .init(status: 0, out: view(), err: "") })
        _ = cli.status(of: url)
        #expect(seen.value.first == "pr")
        let dash = seen.value.firstIndex(of: "--")
        #expect(dash != nil); #expect(seen.value.last == url); #expect(dash == seen.value.count - 2)
    }

    @Test func onlyGitHubAddressesAreEverAsked() {
        let asked = Box(false)
        let cli = GitHubCLI(run: { _ in asked.value = true; return .init(status: 0, out: view(), err: "") })
        #expect(cli.status(of: "--repo=evil/x") == .failure(.unreadable))
        #expect(cli.status(of: "https://example.com/a/b/pull/1") == .failure(.unreadable))
        #expect(!asked.value)
    }

    @Test func whatIsMissingIsTold() {
        #expect(GitHubCLI(run: { _ in nil }).availability() == .notInstalled)
        #expect(GitHubCLI(run: { _ in .init(status: 1, out: Data(), err: "You are not logged into any GitHub hosts") }).availability() == .notSignedIn)
        #expect(GitHubCLI(run: { _ in .init(status: 0, out: Data(), err: "") }).availability() == .ready)
        #expect(GitHubCLI(run: { _ in nil }).status(of: url) == .failure(.notInstalled))
        #expect(GitHubCLI(run: { _ in .init(status: 4, out: Data(), err: "To get started with GitHub CLI, please run:  gh auth login") }).status(of: url) == .failure(.notSignedIn))
    }

    // MARK: the cache
    @Test func eachPullRequestIsAskedOnceAndRememberedUntilItGoesStale() async throws {
        let calls = Box(0)
        let checker = PullRequestChecker(cli: GitHubCLI(run: { _ in calls.value += 1; return .init(status: 0, out: view(rollup: [run("ci", "COMPLETED", "SUCCESS")]), err: "") }))
        let changed = Box(0)
        checker.onUpdate = { changed.value += 1 }
        checker.refresh([url, url])
        try await waitFor { checker.answer(for: url) != nil }
        #expect(calls.value == 1); #expect(changed.value == 1)
        checker.refresh([url])   // fresh: not asked again
        try await Task.sleep(for: .milliseconds(100))
        #expect(calls.value == 1)
        checker.refresh([url], now: Date().addingTimeInterval(120))   // an open one is stale after a minute
        try await waitFor { calls.value == 2 }
        #expect(checker.verified() == [url])
    }

    @Test func aClosedOneIsAskedAgainSoonerThanAMergedOne() async throws {
        let calls = Box(0), state = Box("CLOSED")
        let checker = PullRequestChecker(cli: GitHubCLI(run: { _ in calls.value += 1; return .init(status: 0, out: view(state: state.value), err: "") }))
        checker.refresh([url]); try await waitFor { checker.answer(for: url) != nil }
        checker.refresh([url], now: Date().addingTimeInterval(200)); try await waitFor { calls.value == 2 }   // reopened since
        state.value = "MERGED"
        checker.refresh([url], now: Date().addingTimeInterval(400)); try await waitFor { calls.value == 3 }
        checker.refresh([url], now: Date().addingTimeInterval(1000)); try await Task.sleep(for: .milliseconds(120))
        #expect(calls.value == 3)   // merged is final: not asked again for hours
    }

    @Test func aFailedAskWaitsBeforeTryingAgain() async throws {
        let calls = Box(0)
        let checker = PullRequestChecker(cli: GitHubCLI(run: { _ in calls.value += 1; return .init(status: 1, out: Data(), err: "boom") }))
        checker.refresh([url])
        try await waitFor { calls.value == 1 }
        try await Task.sleep(for: .milliseconds(100))
        checker.refresh([url])
        try await Task.sleep(for: .milliseconds(150))
        #expect(calls.value == 1); #expect(checker.answer(for: url) == nil)
        checker.refresh([url], now: Date().addingTimeInterval(200))
        try await waitFor { calls.value == 2 }
    }

    // MARK: what a session shows
    private func session(_ id: String, _ prs: [PullRequest], idle: TimeInterval = 600, agents: [AgentStatus] = [AgentStatus(kind: .done, text: "Claude finished")]) -> Project {
        var p = Project(id: id, name: id, branch: nil, away: "1h", at: "", headline: "", context: "", next: "", topic: id, app: "claude", agents: agents, steps: [])
        p.prs = prs; p.lastActive = Date().addingTimeInterval(-idle)
        return p
    }
    private func pr(_ n: Int, _ state: PullRequest.State = .open, checks: PullRequest.Checks? = nil, review: PullRequest.Review? = nil) -> PullRequest {
        PullRequest(number: n, repo: "a/b", url: "https://github.com/a/b/pull/\(n)", state: state, checks: checks, review: review)
    }

    @Test func offClearsEverything() {
        var list = [session("a", [pr(1, .merged)])]
        list[0].prNeeds = true
        PullRequests.apply(&list, mode: .off, answer: { _ in nil }, verified: [])
        #expect(list[0].prs.isEmpty); #expect(!list[0].prNeeds)
    }

    @Test func marksShowsMergedAlwaysAndOpenOnlyFromARecentSession() {
        var list = [session("recent", [pr(1), pr(2, .merged)]), session("old", [pr(3), pr(4, .merged)], idle: 5 * 86_400)]
        let asked = PullRequests.apply(&list, mode: .marks, answer: { _ in nil }, verified: [])
        #expect(list[0].prs.map(\.number) == [1, 2])
        #expect(list[1].prs.map(\.number) == [4])
        #expect(asked.isEmpty)   // GitHub is only asked with Checks on
        #expect(!list[0].prNeeds)
    }

    @Test func checksCorrectsAnOpenOneThatHasSinceMerged() {
        // The Claude app still says open, GitHub says merged: an old session shows it, as merged.
        var list = [session("old", [pr(7)], idle: 9 * 86_400)]
        let answered = pr(7, .merged)
        let asked = PullRequests.apply(&list, mode: .checks, answer: { $0 == answered.url ? answered : nil }, verified: [answered.url])
        #expect(list[0].prs.map(\.state) == [.merged]); #expect(asked == [answered.url])
    }

    @Test func checksAskedButNotAnsweredYetTrustsTheAppOnlyForARecentSession() {
        var list = [session("recent", [pr(1)]), session("old", [pr(2)], idle: 9 * 86_400)]
        let asked = PullRequests.apply(&list, mode: .checks, answer: { _ in nil }, verified: [])
        #expect(list[0].prs.map(\.number) == [1]); #expect(list[1].prs.isEmpty)
        #expect(Set(asked) == [pr(1).url, pr(2).url])
    }

    @Test func aFailingPullRequestLiftsAFinishedSessionToNeedingYou() {
        var list = [session("a", [pr(5)])]
        let failing = pr(5, checks: .fail)
        PullRequests.apply(&list, mode: .checks, answer: { _ in failing }, verified: [failing.url])
        #expect(list[0].needsAttention); #expect(list[0].prNeeds)
        #expect(list[0].status.text == "Checks failing on #5"); #expect(list[0].status.kind == "attention")
    }

    @Test func aFailingPullRequestIsNotGivenUpAsOldNewsNorWhenYouLookElsewhere() {
        // A guessed "needs you" from before your last break reads as history; GitHub's word about a pull request is not a guess.
        var list = [session("a", [pr(5)], idle: 3 * 3600)]
        let failing = pr(5, checks: .fail)
        PullRequests.apply(&list, mode: .checks, answer: { _ in failing }, verified: [failing.url])
        let kept = list[0].settled(since: Date())
        #expect(kept.needsAttention); #expect(kept.status.text == "Checks failing on #5")
        let other = session("b", [], idle: 60)
        let moved = Project.movedOn([list[0], other], seen: [list[0].id: Date().timeIntervalSince1970, other.id: Date().timeIntervalSince1970 + 100])
        #expect(moved[0].needsAttention)
        // The same words on a plain guess are history.
        var guess = session("c", [], idle: 3 * 3600, agents: [AgentStatus(kind: .needsYou, text: "Claude asked you something")])
        guess.lastActive = Date().addingTimeInterval(-3 * 3600)
        #expect(!guess.settled(since: Date()).needsAttention)
    }

    @Test func liftingAgainAfterLiveStatusKeepsItWhenNothingElseIsGoingOn() {
        var p = session("a", [pr(5, checks: .fail)])
        p.liftForPullRequest(); #expect(p.needsAttention)
        p.agents = [AgentStatus(kind: .done, text: "Claude finished")]   // live status set it back
        p.liftForPullRequest(); #expect(p.needsAttention)
        p.agents = [AgentStatus(kind: .running, text: "Claude is working")]
        p.liftForPullRequest(); #expect(p.status.kind == "running")
    }

    @Test func aSessionAtWorkOrAskingIsNotLifted() {
        let failing = pr(5, checks: .fail)
        var working = [session("w", [pr(5)], agents: [AgentStatus(kind: .running, text: "Claude is working")])]
        var asking = [session("q", [pr(5)], agents: [AgentStatus(kind: .needsYou, text: "Claude wants to run a command")])]
        PullRequests.apply(&working, mode: .checks, answer: { _ in failing }, verified: [failing.url])
        PullRequests.apply(&asking, mode: .checks, answer: { _ in failing }, verified: [failing.url])
        #expect(!working[0].prNeeds); #expect(working[0].status.text == "Claude is working")
        #expect(!asking[0].prNeeds); #expect(asking[0].status.text == "Claude wants to run a command")
    }

    @Test func marksNeverLiftASession() {
        // Without Checks Perch cannot know a check failed, whatever an old answer said.
        var list = [session("a", [pr(5, checks: .fail)])]
        PullRequests.apply(&list, mode: .marks, answer: { _ in nil }, verified: [])
        #expect(!list[0].prNeeds); #expect(list[0].status.kind == "done")
    }

    @Test func aPassingOrMergedPullRequestLeavesTheSessionAlone() {
        var list = [session("a", [pr(5, checks: .pass, review: .approved)]), session("b", [pr(6, .merged)])]
        PullRequests.apply(&list, mode: .checks, answer: { $0 == pr(5).url ? pr(5, checks: .pass, review: .approved) : pr(6, .merged) }, verified: [pr(5).url, pr(6).url])
        #expect(list.allSatisfy { !$0.prNeeds && $0.status.kind == "done" })
    }

    // MARK: finding them in a session's log
    private let make = "gh pr " + "create"

    @Test func claudeCodesLogShowsTheOneItOpened() {
        var r = PullRequestScan.Reader()
        r.feed(#"{"type":"assistant","message":{"id":"msg_1","content":[{"type":"tool_use","id":"toolu_A","name":"Bash","input":{"command":"git push && \#(make) --title x"}}]}}"#)
        r.feed(#"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"toolu_A","content":"https://github.com/asafofer/perch/pull/127"}]}}"#)
        #expect(r.found == ["https://github.com/asafofer/perch/pull/127"])
    }

    @Test func codexsLogShowsTheOneItOpened() {
        var r = PullRequestScan.Reader()
        r.feed(#"{"type":"response_item","payload":{"type":"custom_tool_call","id":"ctc_1","call_id":"call_9","name":"exec","input":"const r = await tools.exec_command({cmd:\"\#(make) --title t\"})"}}"#)
        r.feed(#"{"type":"response_item","payload":{"type":"custom_tool_call_output","id":"ctco_2","call_id":"call_9","output":"[{'type': 'input_text', 'text': 'remote: Create a pull request https://github.com/asafofer/perch/pull/new/x\\nhttps://github.com/asafofer/perch/pull/127'}]"}}"#)
        #expect(r.found == ["https://github.com/asafofer/perch/pull/127"])
    }

    @Test func pisLogShowsTheOneItOpened() {
        var r = PullRequestScan.Reader()
        r.feed(#"{"type":"message","message":{"role":"assistant","content":[{"type":"toolCall","id":"call_x|fc_1","name":"bash","arguments":{"command":"\#(make)"}}]}}"#)
        r.feed(#"{"type":"message","message":{"role":"toolResult","toolCallId":"call_x|fc_1","toolName":"bash","content":[{"type":"text","text":"https://github.com/a/b/pull/8\n"}]}}"#)
        #expect(r.found == ["https://github.com/a/b/pull/8"])
    }

    @Test func openCodesRecordHasTheCommandAndItsOutputTogether() {
        var r = PullRequestScan.Reader()
        r.feed(#"{"type":"tool","tool":"bash","callID":"call_00","state":{"status":"completed","input":{"command":"\#(make) -t x"},"output":"https://github.com/a/b/pull/3\n"}}"#)
        #expect(r.found == ["https://github.com/a/b/pull/3"])
    }

    @Test func aSearchThatMentionsTheCommandAndListsAddressesIsNotAPullRequest() {
        var r = PullRequestScan.Reader()
        r.feed(#"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_G","name":"Bash","input":{"command":"grep -rn \#(make) docs/ AGENTS.md"}}]}}"#)
        r.feed(#"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"toolu_G","content":"docs/a.md:3: see https://github.com/a/b/pull/94 for how to run it\ndocs/b.md:9: after the PR https://github.com/a/b/pull/95 merged, run it again\nAGENTS.md:7: the command prints the address"}]}}"#)
        #expect(r.found.isEmpty)
        // The address that ends the output is the pull request, even with a hint line before it.
        var s = PullRequestScan.Reader()
        s.feed(#"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_H","name":"Bash","input":{"command":"\#(make) -t x"}}]}}"#)
        s.feed(#"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"toolu_H","content":"Creating pull request for x into main in a/b\n\nhttps://github.com/a/b/pull/9\n"}]}}"#)
        #expect(s.found == ["https://github.com/a/b/pull/9"])
    }

    @Test func anAddressThatIsNotTheResultOfOpeningOneIsNeverTaken() {
        var r = PullRequestScan.Reader()
        // Someone's message, a document, a search: an address with no command that opened it.
        r.feed(#"{"type":"user","message":{"content":"look at https://github.com/a/b/pull/5"}}"#)
        r.feed(#"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_B","name":"Bash","input":{"command":"gh pr view 5"}}]}}"#)
        r.feed(#"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"toolu_B","content":"https://github.com/a/b/pull/5"}]}}"#)
        // The command was made, but the address comes from another call.
        r.feed(#"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_C","name":"Bash","input":{"command":"\#(make)"}}]}}"#)
        r.feed(#"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"toolu_D","content":"https://github.com/a/b/pull/6"}]}}"#)
        // The command and an address in one user message, with no call behind them.
        r.feed(#"{"type":"user","message":{"content":"run \#(make) and tell me if https://github.com/a/b/pull/7 is it"}}"#)
        #expect(r.found.isEmpty)
    }

    @Test func aLogIsReadAsItGrowsAndAgainWhenItShrinks() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("perch-prlog-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        let call = #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_A","name":"Bash","input":{"command":"\#(make)"}}]}}"# + "\n"
        let result = #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"toolu_A","content":"https://github.com/a/b/pull/9"}]}}"# + "\n"
        try call.write(to: file, atomically: true, encoding: .utf8)
        #expect(PullRequestScan.created(in: file).isEmpty)
        let h = try FileHandle(forWritingTo: file); try h.seekToEnd(); try h.write(contentsOf: Data(result.utf8)); try h.close()
        #expect(PullRequestScan.created(in: file) == ["https://github.com/a/b/pull/9"])
        try Data("{}\n".utf8).write(to: file)   // a new, shorter log at the same path
        #expect(PullRequestScan.created(in: file).isEmpty)
    }

    @Test func anAddressFoundInALogIsNotShownUntilGitHubHasSaidWhereItStands() {
        let found = PullRequestScan.requests(["https://github.com/a/b/pull/9", "https://evil.example/a/b/pull/1"])
        #expect(found.map(\.number) == [9]); #expect(found[0].stateKnown == false)
        var list = [session("t", found)]
        PullRequests.apply(&list, mode: .marks, answer: { _ in nil }, verified: [])
        #expect(list[0].prs.isEmpty)   // without Checks there is nothing to say about it
        var checked = [session("t", found)]
        let merged = PullRequest(number: 9, repo: "a/b", url: "https://github.com/a/b/pull/9", state: .merged)
        PullRequests.apply(&checked, mode: .checks, answer: { _ in merged }, verified: [merged.url])
        #expect(checked[0].prs.map(\.state) == [.merged])
        var waiting = [session("t", found)]
        PullRequests.apply(&waiting, mode: .checks, answer: { _ in nil }, verified: [])
        #expect(waiting[0].prs.isEmpty)   // asked, not answered yet
    }

    // MARK: the scan
    @Test func aSessionTheAppListsKeepsItsPullRequests() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("perch-pr-\(UUID().uuidString)/acct/org")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent().deletingLastPathComponent()) }
        let entry: [String: Any] = ["sessionId": "local_a", "cliSessionId": "a", "cwd": "/tmp/x", "title": "T",
                                    "prs": [["prNumber": 70, "url": "https://github.com/asafofer/perch/pull/70", "repo": "asafofer/perch", "state": "MERGED", "own": true]]]
        try json(entry).write(to: dir.appendingPathComponent("local_a.json"))
        let sessions = DesktopSessions(root: dir.deletingLastPathComponent().deletingLastPathComponent())
        #expect(sessions.index()["a"]?.prs.map(\.number) == [70])
    }
}

private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock(); private var v: T
    init(_ v: T) { self.v = v }
    var value: T { get { lock.lock(); defer { lock.unlock() }; return v } set { lock.lock(); v = newValue; lock.unlock() } }
}

private func waitFor(_ ok: @Sendable () -> Bool) async throws {
    for _ in 0..<100 { if ok() { return }; try await Task.sleep(for: .milliseconds(20)) }
    Issue.record("timed out")
}
