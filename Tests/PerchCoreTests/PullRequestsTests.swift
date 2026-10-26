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
            ["prNumber": 70, "url": "https://github.com/asafofer/perch/pull/70", "repo": "asafofer/perch", "state": "MERGED"],
            ["prNumber": 99, "url": "https://github.com/asafofer/perch/pull/99", "repo": "asafofer/perch", "state": "OPEN", "own": true],
        ])
        #expect(prs.map(\.number) == [70, 99])
        #expect(prs.map(\.state) == [.merged, .open])
        #expect(prs[0].repo == "asafofer/perch")
    }

    @Test func aPullRequestTheAppSaysIsNotTheSessionsOwnIsLeftOut() {
        let prs = PullRequests.fromApp([
            ["prNumber": 1, "url": "https://github.com/a/b/pull/1", "repo": "a/b", "state": "OPEN", "own": false],
            ["prNumber": 2, "url": "https://github.com/a/b/pull/2", "repo": "a/b", "state": "OPEN"],   // an older app does not say
        ])
        #expect(prs.map(\.number) == [2])
    }

    @Test func onlyGitHubAddressesAreKept() {
        let prs = PullRequests.fromApp([
            ["prNumber": 1, "url": "http://github.com/a/b/pull/1", "state": "OPEN"],
            ["prNumber": 2, "url": "https://evil.example/a/b/pull/2", "state": "OPEN"],
            ["prNumber": 3, "url": "https://github.com/a/b/pull/3", "state": "OPEN"],
        ])
        #expect(prs.map(\.number) == [3])
        #expect(PullRequests.fromApp("nonsense").isEmpty)
        #expect(PullRequests.fromApp(nil).isEmpty)
    }

    @Test func theSamePullRequestListedTwiceShowsOnce() {
        let e: [String: Any] = ["prNumber": 5, "url": "https://github.com/a/b/pull/5", "state": "MERGED"]
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

    @Test func aFailingOptionalCheckDoesNot() {
        // GitHub calls it UNSTABLE: only checks that do not hold the merge back are failing.
        let pr = GitHubCLI.parse(view(merge: "UNSTABLE", rollup: [run("ci", "COMPLETED", "SUCCESS"), run("preview", "COMPLETED", "FAILURE")]), url: url)!
        #expect(pr.checks == .pass); #expect(!pr.needsYou)
    }

    @Test func checksStillRunningAreRunning() {
        let pr = GitHubCLI.parse(view(rollup: [run("ci", "IN_PROGRESS", ""), run("lint", "COMPLETED", "SUCCESS")]), url: url)!
        #expect(pr.checks == .running); #expect(!pr.needsYou)
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

    // MARK: the scan
    @Test func aSessionTheAppListsKeepsItsPullRequests() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("perch-pr-\(UUID().uuidString)/acct/org")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent().deletingLastPathComponent()) }
        let entry: [String: Any] = ["sessionId": "local_a", "cliSessionId": "a", "cwd": "/tmp/x", "title": "T",
                                    "prs": [["prNumber": 70, "url": "https://github.com/asafofer/perch/pull/70", "repo": "asafofer/perch", "state": "MERGED"]]]
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
