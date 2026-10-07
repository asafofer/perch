import Foundation

public struct AgentStatus: Equatable, Sendable {
    public enum Kind: Sendable { case done, needsYou, idle }
    public let kind: Kind
    public let text: String
    public init(kind: Kind, text: String) { self.kind = kind; self.text = text }
}

public struct Project: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let branch: String?
    public let away: String
    public let headline: String
    public let context: String
    public let next: String
    public let agents: [AgentStatus]
    public let restoreSteps: [String]
    public let needsAttention: Bool

    /// Short form for lists: "You were fixing X." becomes "Fixing X".
    public var subtitle: String {
        var t = headline
        if t.hasPrefix("You were ") { t.removeFirst("You were ".count) }
        if t.hasSuffix(".") { t.removeLast() }
        return t.prefix(1).uppercased() + t.dropFirst()
    }

    public init(id: String, name: String, branch: String?, away: String, headline: String,
                context: String, next: String, agents: [AgentStatus],
                restoreSteps: [String], needsAttention: Bool = false) {
        self.id = id; self.name = name; self.branch = branch; self.away = away
        self.headline = headline; self.context = context; self.next = next
        self.agents = agents; self.restoreSteps = restoreSteps
        self.needsAttention = needsAttention
    }
}

public protocol SessionProviding: Sendable {
    func parkedProjects() -> [Project]
}

public struct FakeSessionProvider: SessionProviding {
    public init() {}
    public func parkedProjects() -> [Project] {
        [
            Project(id: "onboarding", name: "Onboarding flow", branch: "main", away: "2h 14m",
                    headline: "You were fixing the permissions screen.",
                    context: "You swapped the sheet for a popover because it clipped on small windows.",
                    next: "Add the tooltip to the Accessibility row",
                    agents: [AgentStatus(kind: .done, text: "Claude Code done"),
                             AgentStatus(kind: .needsYou, text: "Codex needs you")],
                    restoreSteps: ["Opened 3 windows", "Reopened PermissionsView.swift", "Resumed your Claude Code session"],
                    needsAttention: true),
            Project(id: "website", name: "Website", branch: "feature/hero", away: "yesterday",
                    headline: "You were tightening the hero spacing.",
                    context: "You dropped the full-bleed video because it slowed the page down.",
                    next: "Check the hero at phone width",
                    agents: [AgentStatus(kind: .done, text: "Build passing")],
                    restoreSteps: ["Opened 2 windows", "Started the dev server on :3000", "Resumed your Claude Code session"]),
            Project(id: "finance", name: "Finance", branch: nil, away: "Monday",
                    headline: "You were reconciling September invoices.",
                    context: "You are matching by vendor and amount, not by date.",
                    next: "Two invoices are still unmatched",
                    agents: [AgentStatus(kind: .idle, text: "No agents running")],
                    restoreSteps: ["Opened 2 windows", "Reopened Invoices, September", "Scrolled to row 41"]),
        ]
    }
}
