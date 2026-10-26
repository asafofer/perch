import Foundation
import PerchCore

/// Pull requests as the app lives with them: how they are shown (Settings), whether the GitHub CLI can be used, what GitHub
/// last said, and what each session ends up showing.
final class PullRequestState: @unchecked Sendable {
    static let shared = PullRequestState()
    let checker = PullRequestChecker()
    private let lock = NSLock()
    private var known: GitHubCLI.Availability?
    private var askedAt = Date.distantPast
    private var asking = false

    /// Whether the GitHub CLI is installed and signed in, as last asked. Nil until the first answer.
    var availability: GitHubCLI.Availability? { lock.lock(); defer { lock.unlock() }; return known }

    /// How pull requests are shown now: Checks only while the CLI works, marks otherwise.
    var mode: PullRequests.Mode {
        guard Prefs.prShow else { return .off }
        return Prefs.prChecks && availability == .ready ? .checks : .marks
    }

    /// Asks again whether the CLI works (at most every 30 s unless forced), off the main thread. `done` runs on the main thread when it changed.
    func refreshAvailability(force: Bool = false, done: (() -> Void)? = nil) {
        lock.lock()
        if asking || (!force && Date().timeIntervalSince(askedAt) < 30) { lock.unlock(); return }
        asking = true; lock.unlock()
        DispatchQueue.global(qos: .utility).async { [self] in
            let now = GitHubCLI.system.availability()
            lock.lock(); let changed = known != now; known = now; askedAt = Date(); asking = false; lock.unlock()
            if changed { checker.reset() }
            if changed { DispatchQueue.main.async { done?() } }
        }
    }

    /// What each session shows: its pull requests as the mode allows, with what GitHub said when Checks is on, and a session
    /// whose pull request needs you reads as needing you (unless it is already at work or asking something).
    func apply(_ projects: inout [Project], now: Date = Date()) {
        let mode = self.mode
        guard mode != .off else { for i in projects.indices { projects[i].prs = []; projects[i].prNeeds = false }; return }
        let verified = mode == .checks ? checker.verified() : []
        var urls: [String] = []
        for i in projects.indices where !projects[i].prs.isEmpty {
            var list = projects[i].prs
            if mode == .checks { urls += list.map(\.url); list = list.map { checker.answer(for: $0.url) ?? $0 } }
            projects[i].prs = PullRequests.visible(list, mode: mode, idle: now.timeIntervalSince(projects[i].lastActive ?? .distantPast), verified: verified)
            if mode == .checks, let pr = projects[i].prs.first(where: \.needsYou), projects[i].ask == nil,
               !projects[i].agents.contains(where: { $0.kind == .needsYou || $0.kind == .running }) {
                projects[i].agents = [AgentStatus(kind: .needsYou, text: pr.needsWords, app: projects[i].app)]
                projects[i].prNeeds = true
            }
        }
        if mode == .checks { checker.refresh(urls) }
    }
}
