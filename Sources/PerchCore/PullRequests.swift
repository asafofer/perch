import Foundation

/// A pull request a session worked on, as the page draws it: a mark on the row and the card, a label on hover.
/// Two sources: the Claude app keeps a list of them per session (its state only, kept while the session is in use),
/// and the GitHub CLI, when you switch Checks on, says how each one stands now.
public struct PullRequest: Equatable, Sendable {
    public enum State: String, Sendable { case open, draft, merged, closed }
    public enum Checks: String, Sendable { case pass, fail, running }
    public enum Review: String, Sendable { case approved, changes }
    public var number: Int
    public var repo: String
    public var url: String
    public var state: State
    public var title: String?
    public var checks: Checks?
    public var review: Review?
    public var conflict = false
    /// False when only the address is known (found in a session's log): its state is GitHub's to say, once asked.
    public var stateKnown = true

    public init(number: Int, repo: String, url: String, state: State, title: String? = nil, checks: Checks? = nil, review: Review? = nil, conflict: Bool = false) {
        self.number = number; self.repo = repo; self.url = url; self.state = state
        self.title = title; self.checks = checks; self.review = review; self.conflict = conflict
    }

    /// Yours to act on: an open pull request whose checks fail, that a reviewer wants changed, or that does not merge cleanly.
    public var needsYou: Bool { state == .open && (checks == .fail || review == .changes || conflict) }

    /// What the session's status says when this is why it needs you: "Checks failing on #448".
    public var needsWords: String {
        let why = checks == .fail ? "Checks failing" : review == .changes ? "Changes requested" : "Merge conflicts"
        return "\(why) on #\(number)"
    }
}

public enum PullRequests {
    /// How Perch shows pull requests: not at all, as marks from the Claude app's own list, or with a check on GitHub.
    public enum Mode: String, Sendable { case off, marks, checks }

    /// The Claude app's own state of an open pull request is only kept while the session is in use: older than this, it is
    /// often out of date (a pull request merged since still reads open), so it is not shown. Merged and closed are final.
    public static let staleAfter: TimeInterval = 2 * 86_400

    /// The `prs` of a Claude app session file: [{prNumber, repo, url, state: OPEN|MERGED|CLOSED, branch, own?}], only the session's own.
    public static func fromApp(_ raw: Any?, sessionBranches: [String] = []) -> [PullRequest] {
        guard let list = raw as? [[String: Any]] else { return [] }
        var seen = Set<String>(), out: [PullRequest] = []
        for e in list {
            guard let number = (e["prNumber"] as? Int) ?? (e["number"] as? Int), let url = e["url"] as? String, isGitHub(url),
                  seen.insert(url).inserted else { continue }
            // The app lists what the session touched too, a pull request it only read among them. `own` says which are its own; where it
            // does not say, a pull request on the session's own branch is, and any other is left to the session's log to vouch for.
            switch e["own"] as? Bool {
            case false?: continue
            case nil: guard let b = e["branch"] as? String, sessionBranches.contains(b) else { continue }
            default: break
            }
            let state: PullRequest.State
            switch (e["state"] as? String ?? "").uppercased() {
            case "MERGED": state = .merged
            case "CLOSED": state = .closed
            case "DRAFT": state = .draft
            default: state = e["isDraft"] as? Bool == true ? .draft : .open
            }
            out.append(PullRequest(number: number, repo: e["repo"] as? String ?? repoOf(url) ?? "", url: url, state: state))
        }
        return out
    }

    /// An https address on a GitHub host: all that is ever opened from a pull request's mark.
    public static func isGitHub(_ url: String) -> Bool {
        guard let u = URL(string: url), u.scheme == "https", let host = u.host?.lowercased() else { return false }
        return host == "github.com" || host.hasSuffix(".github.com") || host.hasSuffix(".ghe.com")
    }

    /// "owner/name" out of https://github.com/owner/name/pull/12.
    static func repoOf(_ url: String) -> String? {
        let parts = (URL(string: url)?.pathComponents ?? []).filter { $0 != "/" }
        return parts.count >= 2 ? parts[0] + "/" + parts[1] : nil
    }

    /// What a session shows. Nothing when Perch is told to show none. An open pull request in a session nobody has used for
    /// two days is left out unless GitHub itself was asked (`verified`): the Claude app's word may be stale.
    public static func visible(_ prs: [PullRequest], mode: Mode, idle: TimeInterval, verified: Set<String> = []) -> [PullRequest] {
        guard mode != .off else { return [] }
        return prs.filter { pr in
            if !pr.stateKnown && !verified.contains(pr.url) { return false }
            switch pr.state {
            case .merged, .closed: return true
            case .open, .draft: return idle <= staleAfter || verified.contains(pr.url)
            }
        }
    }

    /// What every session shows, in place: its pull requests as the mode allows, with what GitHub said (`answer`) when Checks is on,
    /// and a session whose pull request needs you reads as needing you, unless it is at work or asking something already.
    /// Returns the addresses GitHub should be asked about.
    @discardableResult
    public static func apply(_ projects: inout [Project], mode: Mode, answer: (String) -> PullRequest?, verified: Set<String>, now: Date = Date()) -> [String] {
        guard mode != .off else { for i in projects.indices { projects[i].prs = []; projects[i].prNeeds = false }; return [] }
        var urls: [String] = []
        for i in projects.indices where !projects[i].prs.isEmpty {
            var list = projects[i].prs
            if mode == .checks { urls += list.map(\.url); list = list.map { answer($0.url) ?? $0 } }
            projects[i].prs = visible(list, mode: mode, idle: now.timeIntervalSince(projects[i].lastActive ?? .distantPast), verified: verified)
            if mode == .checks, let pr = projects[i].prs.first(where: \.needsYou), projects[i].ask == nil,
               !projects[i].agents.contains(where: { $0.kind == .needsYou || $0.kind == .running }) {
                projects[i].agents = [AgentStatus(kind: .needsYou, text: pr.needsWords, app: projects[i].app)]
                projects[i].prNeeds = true
            }
        }
        return urls
    }

    /// The pull request a session's mark is about, by what matters most: the one that needs you, then open, draft, merged, closed.
    public static func top(_ prs: [PullRequest]) -> PullRequest? {
        func rank(_ p: PullRequest) -> Int {
            if p.needsYou { return 0 }
            switch p.state { case .open: return 1; case .draft: return 2; case .merged: return 3; case .closed: return 4 }
        }
        return prs.min { rank($0) < rank($1) }
    }
}

// MARK: the GitHub CLI

/// The GitHub CLI (`gh`), run read only, with the login you already have. Perch holds no token of its own.
public struct GitHubCLI: Sendable {
    public enum Availability: Equatable, Sendable { case ready, notInstalled, notSignedIn }
    public struct Result: Sendable { public let status: Int32; public let out: Data; public let err: String
        public init(status: Int32, out: Data, err: String) { self.status = status; self.out = out; self.err = err } }

    /// Runs `gh` with these arguments. Nil when it cannot be started. Injected in tests.
    public var run: @Sendable ([String]) -> Result?
    public init(run: @escaping @Sendable ([String]) -> Result?) { self.run = run }

    /// The real one: `gh` found where it is installed (an app starts with a bare PATH, so Homebrew's folder is not on it).
    public static let system = GitHubCLI(run: { args in
        guard let path = locate() else { return nil }
        return execute(path, args)
    })

    private static let located = NSLock()
    nonisolated(unsafe) private static var found: (done: Bool, path: String?) = (false, nil)

    /// Where `gh` is: the usual install folders, then whatever a login shell finds. Asked once, until it is not found.
    static func locate() -> String? {
        located.lock(); defer { located.unlock() }
        // For trying Perch against a stand-in (PERCH_GH=<path>): the one place it looks, so a missing file reads as no GitHub CLI.
        if let forced = ProcessInfo.processInfo.environment["PERCH_GH"] { return FileManager.default.isExecutableFile(atPath: forced) ? forced : nil }
        if found.done, let p = found.path, FileManager.default.isExecutableFile(atPath: p) { return p }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var path = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh", home + "/.local/bin/gh", "/opt/local/bin/gh"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
        if path == nil, let r = execute("/bin/zsh", ["-lc", "command -v gh"], timeout: 8), r.status == 0 {
            let p = String(decoding: r.out, as: UTF8.self).split(separator: "\n").last.map(String.init)?.trimmingCharacters(in: .whitespaces)
            if let p, p.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: p) { path = p }
        }
        found = (path != nil, path)
        return path
    }

    /// Runs a tool, reading its output while it runs (a full pipe would wait for ever) and stopping it after `timeout` seconds.
    static func execute(_ exe: String, _ args: [String], timeout: TimeInterval = 20) -> Result? {
        let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["GH_PROMPT_DISABLED"] = "1"; env["NO_COLOR"] = "1"; env["GH_NO_UPDATE_NOTIFIER"] = "1"; env["GH_SPINNER_DISABLED"] = "1"; env["GH_NO_EXTENSION_UPDATE_NOTIFIER"] = "1"
        p.environment = env
        let out = Pipe(), err = Pipe(); p.standardOutput = out; p.standardError = err; p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        var errData = Data()
        let errDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { errData = err.fileHandleForReading.readDataToEndOfFile(); errDone.signal() }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit(); killer.cancel(); errDone.wait()
        return Result(status: p.terminationStatus, out: data, err: String(decoding: errData, as: UTF8.self))
    }

    /// Whether Checks can work here: the CLI is installed and has a login.
    public func availability() -> Availability {
        guard let r = run(["auth", "status"]) else { return .notInstalled }
        return r.status == 0 ? .ready : .notSignedIn
    }

    public enum Failure: Error, Equatable, Sendable { case notInstalled, notSignedIn, unreadable, failed(String) }

    /// How one pull request stands now, from its address.
    public func status(of url: String) -> Swift.Result<PullRequest, Failure> {
        guard PullRequests.isGitHub(url) else { return .failure(.unreadable) }
        let fields = "number,title,url,state,isDraft,reviewDecision,mergeable,mergeStateStatus,statusCheckRollup"
        // `--` ends the options: whatever follows is the address, never a flag.
        guard let r = run(["pr", "view", "--json", fields, "--", url]) else { return .failure(.notInstalled) }
        guard r.status == 0 else {
            if r.status == 4 || r.err.contains("gh auth login") { return .failure(.notSignedIn) }
            return .failure(.failed(String(r.err.prefix(200))))
        }
        guard let pr = Self.parse(r.out, url: url) else { return .failure(.unreadable) }
        return .success(pr)
    }

    /// `gh pr view --json …` into a pull request. Checks count only when they hold the merge back: GitHub calls a pull request
    /// with only optional checks failing UNSTABLE, and that is not a reason to look at it.
    public static func parse(_ data: Data, url: String) -> PullRequest? {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let number = o["number"] as? Int else { return nil }
        let state: PullRequest.State
        switch (o["state"] as? String ?? "").uppercased() {
        case "MERGED": state = .merged
        case "CLOSED": state = .closed
        default: state = o["isDraft"] as? Bool == true ? .draft : .open
        }
        var pr = PullRequest(number: number, repo: PullRequests.repoOf(url) ?? "", url: (o["url"] as? String).flatMap { PullRequests.isGitHub($0) ? $0 : nil } ?? url,
                             state: state, title: (o["title"] as? String).flatMap { $0.isEmpty ? nil : $0 })
        guard state == .open || state == .draft else { return pr }
        let merge = (o["mergeStateStatus"] as? String ?? "").uppercased()
        pr.conflict = (o["mergeable"] as? String ?? "").uppercased() == "CONFLICTING" || merge == "DIRTY"
        switch (o["reviewDecision"] as? String ?? "").uppercased() {
        case "APPROVED": pr.review = .approved
        case "CHANGES_REQUESTED": pr.review = .changes
        default: break
        }
        var failing = false, running = false, any = false
        // A check run again (a reopened pull request, a re-run) is listed once for each run: the newest of each name is the one that stands.
        var newest: [String: (at: String, c: [String: Any])] = [:], anon: [[String: Any]] = []
        for c in (o["statusCheckRollup"] as? [[String: Any]]) ?? [] {
            guard let name = (c["name"] as? String) ?? (c["context"] as? String) else { anon.append(c); continue }
            let at = (c["completedAt"] as? String).flatMap { $0.hasPrefix("0001") ? nil : $0 } ?? (c["startedAt"] as? String) ?? (c["createdAt"] as? String) ?? ""
            let key = ((c["workflowName"] as? String) ?? "") + "/" + name
            if let was = newest[key], was.at >= at { continue }
            newest[key] = (at, c)
        }
        for c in newest.values.map(\.c) + anon {
            if c["__typename"] as? String == "StatusContext" || (c["context"] != nil && c["status"] == nil) {
                // A commit status.
                switch (c["state"] as? String ?? "").uppercased() {
                case "FAILURE", "ERROR": failing = true; any = true
                case "PENDING", "EXPECTED": running = true; any = true
                case "SUCCESS": any = true
                default: break
                }
                continue
            }
            // A check run.
            let status = (c["status"] as? String ?? "").uppercased(), conclusion = (c["conclusion"] as? String ?? "").uppercased()
            if status != "COMPLETED" && !status.isEmpty { running = true; any = true; continue }
            switch conclusion {
            case "FAILURE", "TIMED_OUT", "STARTUP_FAILURE", "ACTION_REQUIRED", "CANCELLED": failing = true; any = true
            case "SUCCESS": any = true
            default: break   // skipped, neutral, stale: they say nothing
            }
        }
        if failing && merge != "UNSTABLE" { pr.checks = .fail }
        else if running { pr.checks = .running }
        else if any { pr.checks = .pass }
        return pr
    }
}

// MARK: asking GitHub, with care

/// How each pull request stands on GitHub, asked for the sessions in the list and kept: an open one for a minute, the rest
/// for hours, a failure for two minutes. Never more than three at once, and only for what the list shows.
public final class PullRequestChecker: @unchecked Sendable {
    public var cli: GitHubCLI
    /// Called (off the main thread) when an answer changed what the list would show.
    public var onUpdate: (@Sendable () -> Void)?
    private let lock = NSLock()
    private var answers: [String: (pr: PullRequest, at: Date)] = [:]
    private var failures: [String: Date] = [:]
    private var inFlight = Set<String>()
    private let queue: OperationQueue = { let q = OperationQueue(); q.maxConcurrentOperationCount = 3; q.qualityOfService = .utility; return q }()
    /// How long an answer stands: an open one a minute, a closed one three (it can be reopened), a merged one for hours (it is final).
    public var openFor: TimeInterval = 60, closedFor: TimeInterval = 180, restFor: TimeInterval = 6 * 3600, failedFor: TimeInterval = 120

    public init(cli: GitHubCLI = .system) { self.cli = cli }

    /// What GitHub last said about it, if it was asked.
    public func answer(for url: String) -> PullRequest? { lock.lock(); defer { lock.unlock() }; return answers[url]?.pr }

    /// The addresses GitHub has answered for.
    public func verified() -> Set<String> { lock.lock(); defer { lock.unlock() }; return Set(answers.keys) }

    /// Asks for the ones that are not known or have gone stale, in the background.
    public func refresh(_ urls: [String], now: Date = Date()) {
        lock.lock()
        var once = Set<String>()
        let due = urls.filter { url in
            guard once.insert(url).inserted, !inFlight.contains(url) else { return false }
            if let f = failures[url], now.timeIntervalSince(f) < failedFor { return false }
            if let a = answers[url] { return now.timeIntervalSince(a.at) >= (a.pr.state == .open || a.pr.state == .draft ? openFor : a.pr.state == .closed ? closedFor : restFor) }
            return true
        }
        due.forEach { inFlight.insert($0) }
        lock.unlock()
        for url in due {
            queue.addOperation { [weak self] in
                guard let self else { return }
                let result = self.cli.status(of: url)
                self.lock.lock(); self.inFlight.remove(url)
                var changed = false
                switch result {
                case .success(let pr): changed = self.answers[url]?.pr != pr; self.answers[url] = (pr, Date()); self.failures[url] = nil
                case .failure: self.failures[url] = Date()
                }
                self.lock.unlock()
                if changed { self.onUpdate?() }
            }
        }
    }

    /// Forgets everything (Checks was switched off, or a login changed).
    public func reset() { lock.lock(); answers = [:]; failures = [:]; lock.unlock() }
}
