import Foundation

public struct AgentStatus: Equatable, Sendable {
    public enum Kind: Sendable { case done, needsYou, idle, running }
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
    /// The Claude app's own id for this session ("local_…"). When set, Pick up opens it in the app instead of Terminal.
    public let desktopSessionId: String?
    /// When the agent last said something. What "while you were away" is measured against.
    public var lastActive: Date?
    /// What the agent is asking right now, when its hooks said so. The card can answer it.
    public var ask: Ask?
    /// The last time the session was in front of you in its app (the Claude app records it). Changes before it are not news.
    public var focusedAt: Date?
    /// While it works: the step it is on ("Running `swift test`"). The card shows it on a Now row.
    public var now: String?
    /// Started in a terminal (Claude Code or Codex on the command line), not in an app. Pick up goes back to its tab.
    public var terminal = false
    /// The terminal app it runs in, or would open in (a bundle id).
    public var via: String?

    public init(id: String, name: String, branch: String?, away: String, at: String, headline: String,
                context: String, next: String, topic: String, app: String,
                agents: [AgentStatus], steps: [RestoreStep], sessionId: String? = nil, cwd: String? = nil, desktopSessionId: String? = nil) {
        self.id = id; self.name = name; self.branch = branch; self.away = away; self.at = at
        self.headline = headline; self.context = context; self.next = next; self.topic = topic
        self.app = app; self.agents = agents; self.steps = steps; self.sessionId = sessionId; self.cwd = cwd; self.desktopSessionId = desktopSessionId
    }

    public var needsAttention: Bool { agents.contains { $0.kind == .needsYou } }

    /// The one status worth showing: whatever needs you, else what finished, else idle.
    public var status: (kind: String, text: String, app: String) {
        if let a = agents.first(where: { $0.kind == .needsYou }) { return ("attention", a.text, a.app) }
        if let a = agents.first(where: { $0.kind == .running }) { return ("running", a.text, a.app) }
        if let a = agents.first(where: { $0.kind == .done }) { return ("done", a.text, a.app) }
        return ("idle", agents.first?.text ?? "No agents running", agents.first?.app ?? "claude")
    }
}

public protocol SessionProviding: Sendable {
    func parkedProjects() -> [Project]
}

public struct FakeSessionProvider: SessionProviding {
    public init() {}
    /// The same sessions the design page uses, for demos and the README screenshots.
    public func parkedProjects() -> [Project] {
        var asks = Project(id: "onboarding", name: "Onboarding flow", branch: "main", away: "4m", at: "11:32 AM",
                           headline: "You were fixing the permissions screen.",
                           context: "Swapped the sheet for a popover because it clipped on small windows.",
                           next: "", topic: "Permissions screen", app: "claude",
                           agents: [AgentStatus(kind: .needsYou, text: "Claude wants to run a command")], steps: [])
        asks.ask = Ask(id: "demo", agent: "claude", tool: "Bash", input: ["command": "npm run build && npm test -- --watch=false"])
        let now = Date()
        asks.lastActive = now.addingTimeInterval(-240)
        var list = [
            asks,
            Project(id: "website", name: "Website", branch: "feature/hero", away: "48m", at: "10:44 AM",
                    headline: "You were tightening the hero spacing.",
                    context: "The hero now fits at phone width. The full-bleed video is gone because it slowed the page.",
                    next: "Check the hero on a real phone", topic: "Hero spacing", app: "claude",
                    agents: [AgentStatus(kind: .done, text: "Claude finished")], steps: []),
            Project(id: "docs", name: "Docs", branch: "main", away: "1m", at: "11:58 AM",
                    headline: "You were rewriting the install guide.",
                    context: "Moved the setup steps above troubleshooting and cut the duplicate FAQ.",
                    next: "", topic: "Install guide", app: "codex",
                    agents: [AgentStatus(kind: .running, text: "Codex is working", app: "codex")], steps: []),
            Project(id: "finance", name: "Finance", branch: nil, away: "3d", at: "Mon 3:40 PM",
                    headline: "You were reconciling September invoices.",
                    context: "Matched 41 of 43 invoices by vendor and amount; two are still open.",
                    next: "", topic: "September invoices", app: "claude",
                    agents: [AgentStatus(kind: .idle, text: "Claude finished")], steps: []),
        ]
        for (i, ago) in [(1, 2880.0), (2, 60), (3, 3 * 86_400)] { list[i].lastActive = now.addingTimeInterval(-ago) }
        list[2].now = "Editing install.md"
        return list
    }
}

/// Typing in the list narrows it: every word you type must appear in the project's name or title, in any case or accent.
public enum ListFilter {
    public static func matches(_ p: Project, _ query: String) -> Bool {
        let hay = (p.name + " " + p.topic).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return query.split(whereSeparator: \.isWhitespace).allSatisfy { hay.contains(String($0).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)) }
    }
    /// The rows that stay, by their place in the full list. All of them when nothing is typed.
    public static func shown(_ list: [Project], _ query: String) -> [Int] {
        list.indices.filter { query.trimmingCharacters(in: .whitespaces).isEmpty || matches(list[$0], query) }
    }

    /// The list's sections: what needs you, then what you touched today, then the rest.
    public enum Section: String { case needsYou = "Needs you", today = "Today", earlier = "Earlier" }
    public static func section(_ p: Project, now: Date, calendar: Calendar = .current) -> Section {
        if p.needsAttention { return .needsYou }
        guard let at = p.lastActive else { return .earlier }
        return calendar.isDate(at, inSameDayAs: now) ? .today : .earlier
    }
    /// The rows that stay, in the order the list draws them: by section, newest first in each. Up and Down follow it.
    public static func ordered(_ list: [Project], _ query: String, now: Date, calendar: Calendar = .current) -> [Int] {
        let rank: (Int) -> Int = { [.needsYou: 0, .today: 1, .earlier: 2][section(list[$0], now: now, calendar: calendar)] ?? 2 }
        return shown(list, query).sorted { a, b in
            let ra = rank(a), rb = rank(b)
            if ra != rb { return ra < rb }
            let ta = list[a].lastActive ?? .distantPast, tb = list[b].lastActive ?? .distantPast
            return ta != tb ? ta > tb : a < b
        }
    }
}
