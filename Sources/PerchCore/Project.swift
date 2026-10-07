import Foundation

public struct AgentStatus: Equatable, Sendable {
    public enum Kind: Sendable { case done, needsYou, idle }
    public let kind: Kind
    public let text: String
    /// Which app's icon represents this agent: "claude", "codex".
    public let app: String
    public init(kind: Kind, text: String, app: String = "claude") { self.kind = kind; self.text = text; self.app = app }
}

public struct RestoreStep: Equatable, Sendable {
    /// One of the icon names the UI knows: "win", "file", "term".
    public let icon: String
    public let text: String
    public init(icon: String, text: String) { self.icon = icon; self.text = text }
}

public struct Project: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let branch: String?
    public let away: String          // "2h 14m"
    public let at: String            // "11:32 AM"
    public let headline: String
    public let context: String
    public let next: String
    public let topic: String         // short label for lists
    public let app: String           // which app icon the UI shows
    public let agents: [AgentStatus]
    public let steps: [RestoreStep]
    /// Set for real sessions: what Pick up resumes. Nil for sample data, which does nothing.
    public let sessionId: String?
    public let cwd: String?

    public init(id: String, name: String, branch: String?, away: String, at: String, headline: String,
                context: String, next: String, topic: String, app: String,
                agents: [AgentStatus], steps: [RestoreStep], sessionId: String? = nil, cwd: String? = nil) {
        self.id = id; self.name = name; self.branch = branch; self.away = away; self.at = at
        self.headline = headline; self.context = context; self.next = next; self.topic = topic
        self.app = app; self.agents = agents; self.steps = steps; self.sessionId = sessionId; self.cwd = cwd
    }

    public var needsAttention: Bool { agents.contains { $0.kind == .needsYou } }

    /// The one status worth showing: whatever needs you, else what finished, else idle.
    public var status: (kind: String, text: String, app: String) {
        if let a = agents.first(where: { $0.kind == .needsYou }) { return ("attention", a.text, a.app) }
        if let a = agents.first(where: { $0.kind == .done }) { return ("done", a.text, a.app) }
        return ("idle", agents.first?.text ?? "No agents running", agents.first?.app ?? "claude")
    }
}

public protocol SessionProviding: Sendable {
    func parkedProjects() -> [Project]
}

public struct FakeSessionProvider: SessionProviding {
    public init() {}
    public func parkedProjects() -> [Project] {
        [
            Project(id: "onboarding", name: "Onboarding flow", branch: "main", away: "2h 14m", at: "11:32 AM",
                    headline: "You were fixing the permissions screen.",
                    context: "You swapped the sheet for a popover because it clipped on small windows.",
                    next: "Add the tooltip to the Accessibility row", topic: "Permissions screen", app: "xcode",
                    agents: [AgentStatus(kind: .done, text: "Claude Code done"), AgentStatus(kind: .needsYou, text: "Codex needs you", app: "codex")],
                    steps: [RestoreStep(icon: "win", text: "Put 3 windows back"),
                            RestoreStep(icon: "file", text: "Opened PermissionsView.swift"),
                            RestoreStep(icon: "term", text: "Resumed your Claude Code session")]),
            Project(id: "website", name: "Website", branch: "feature/hero", away: "20h", at: "Yesterday 5:05 PM",
                    headline: "You were tightening the hero spacing.",
                    context: "You dropped the full-bleed video because it slowed the page down.",
                    next: "Check the hero at phone width", topic: "Hero spacing", app: "claude",
                    agents: [AgentStatus(kind: .done, text: "Build passing")],
                    steps: [RestoreStep(icon: "win", text: "Put 2 windows back"),
                            RestoreStep(icon: "term", text: "Started the dev server on :3000"),
                            RestoreStep(icon: "term", text: "Resumed your Claude Code session")]),
            Project(id: "finance", name: "Finance", branch: nil, away: "3d", at: "Mon 3:40 PM",
                    headline: "You were reconciling September invoices.",
                    context: "You are matching by vendor and amount, not by date.",
                    next: "Two invoices are still unmatched", topic: "September invoices", app: "numbers",
                    agents: [AgentStatus(kind: .idle, text: "No agents running")],
                    steps: [RestoreStep(icon: "win", text: "Put 2 windows back"),
                            RestoreStep(icon: "file", text: "Opened Invoices, September"),
                            RestoreStep(icon: "file", text: "Scrolled to row 41")]),
        ]
    }
}
