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
    public let goal: String
    public let decided: String
    public let next: String
    public let agents: [AgentStatus]
    public let restoreSteps: [String]
    public let needsAttention: Bool

    public init(id: String, name: String, branch: String?, away: String, goal: String,
                decided: String, next: String, agents: [AgentStatus],
                restoreSteps: [String], needsAttention: Bool = false) {
        self.id = id; self.name = name; self.branch = branch; self.away = away
        self.goal = goal; self.decided = decided; self.next = next
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
                    goal: "Fixing the permissions screen",
                    decided: "Switched the sheet to a popover. The sheet clipped on small windows.",
                    next: "Add the tooltip to the Accessibility row",
                    agents: [AgentStatus(kind: .done, text: "Claude Code · done, 2 files"),
                             AgentStatus(kind: .needsYou, text: "Codex · needs you")],
                    restoreSteps: ["Opened 3 windows", "Reopened PermissionsView.swift", "Resumed your Claude Code session"],
                    needsAttention: true),
            Project(id: "website", name: "Website", branch: "feature/hero", away: "yesterday",
                    goal: "Tightening the hero spacing",
                    decided: "Dropped the full-bleed video. It hurt load time.",
                    next: "Check the hero at phone width",
                    agents: [AgentStatus(kind: .done, text: "Claude Code · build passing")],
                    restoreSteps: ["Opened 2 windows", "Started the dev server on :3000", "Resumed your Claude Code session"]),
            Project(id: "finance", name: "Finance", branch: nil, away: "Monday",
                    goal: "Reconciling September invoices",
                    decided: "Matching by vendor and amount, not by date.",
                    next: "Two invoices are still unmatched",
                    agents: [AgentStatus(kind: .idle, text: "No agents running")],
                    restoreSteps: ["Opened 2 windows", "Reopened Invoices, September", "Scrolled to row 41"]),
        ]
    }
}
