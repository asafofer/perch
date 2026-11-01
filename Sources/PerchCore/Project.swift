import Foundation

public struct AgentStatus: Equatable, Sendable {
    public enum Kind: Sendable { case done, needsYou, idle, running }
    public let kind: Kind
    public let text: String
    /// Which agent's icon represents it: an Agent id ("claude", "codex", "opencode", "pi").
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
    public var headline: String
    public var context: String
    public var next: String
    public let topic: String         // short label for lists
    public let app: String           // which app icon the UI shows
    public var agents: [AgentStatus]
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
    /// Its turn is over but not its work: helpers, a watch or a command it left in the background have not reported back,
    /// and it carries on when they do. A Stop hook does not make it done.
    public var waiting = false
    /// Conductor's id for the workspace the session lives in. When set, Pick up opens it in Conductor.
    public var conductor: String?
    /// Started in a terminal (Claude Code or Codex on the command line), not in an app. Pick up goes back to its tab.
    public var terminal = false
    /// Only small talk so far (`Recap.isTrivial`), in a terminal: listed only while its agent still runs there, so a
    /// "hello" does not vanish the moment its reply lands, and is gone once you close it.
    public var smallTalk = false
    /// The terminal app it runs in, or would open in (a bundle id). In herdr, the terminal that shows herdr.
    public var via: String?
    /// The multiplexer it runs in, when that is not the terminal itself: "herdr".
    public var host: String?
    /// The process running it in a terminal, when the last scan found one. Pick up goes to exactly that one.
    public var pid: Int32?
    /// Where that process lives (`Spot.key`): compared with what is in front of you to tell the session you are in.
    public var spot: String?
    /// When the session began: which of several agents in one folder is running it depends on it.
    public var startedAt: Date?
    /// The agent's own last message, as it wrote it (its end, when it is long). The card shows it while you reply.
    public var said: String?
    /// Your own last message, as you wrote it. The card shows it above the agent's while you reply.
    public var asked: String?
    /// Your message came after the agent's: it has not answered yet, so the card shows yours below.
    public var askedLast = false
    /// When you stopped it (Esc, or Stop in the app), from the transcript. Claude sends no hook for a stop.
    public var stoppedAt: Date?
    /// Its transcript ends on a tool call with no result yet: running, or waiting for your OK.
    public var toolOpen = false
    /// Its own app says how it stands (a Claude task: the app's `running`, `awaiting`, `idle`), not a guess from a transcript:
    /// a wait it reports stands until the app says otherwise, however old.
    public var appSays = false
    /// Its own avatar where the agent draws one per session ("shape:color", a Grok Bot bot): the row and card wear it.
    public var avatar: String?
    /// The pull requests it worked on, as it shows them (`PullRequests.visible`, and what GitHub said when Checks is on).
    public var prs: [PullRequest] = []
    /// A pull request needs you, and that is why the session reads as needing you (so the notch can tell it from a question).
    public var prNeeds = false

    public init(id: String, name: String, branch: String?, away: String, at: String, headline: String,
                context: String, next: String, topic: String, app: String,
                agents: [AgentStatus], steps: [RestoreStep], sessionId: String? = nil, cwd: String? = nil, desktopSessionId: String? = nil) {
        self.id = id; self.name = name; self.branch = branch; self.away = away; self.at = at
        self.headline = headline; self.context = context; self.next = next; self.topic = topic
        self.app = app; self.agents = agents; self.steps = steps; self.sessionId = sessionId; self.cwd = cwd; self.desktopSessionId = desktopSessionId
    }

    public var needsAttention: Bool { agents.contains { $0.kind == .needsYou } }

    /// A terminal session no process runs any more (the scan found none): a tool call it left open waits on no one, so it
    /// is neither asking you anything nor at work. Sample data (no session id) is left as it is.
    public func agentGone() -> Project {
        guard terminal, pid == nil, sessionId != nil, needsAttention || status.kind == "running", ask != nil || toolOpen else { return self }
        if ask?.answerable == true { return self }   // held by its hook, which settles it when it goes
        var p = self
        p.agents = [AgentStatus(kind: .idle, text: "\(Agent.of(app).name) stopped mid-task", app: app)]
        p.ask = nil; p.next = ""; p.now = nil
        return p
    }

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
        // The other agents: OpenCode at work in Ghostty, and pi finished in a herdr pane shown in Ghostty.
        var tui = Project(id: "tui", name: "tui-kit", branch: "main", away: "2m", at: "12:03 PM",
                          headline: "Keyboard focus for the table.",
                          context: "Moving focus with the arrow keys, then making Tab leave the table.",
                          next: "", topic: "Keyboard focus for the table component", app: "opencode",
                          agents: [AgentStatus(kind: .running, text: "OpenCode is working", app: "opencode")], steps: [])
        tui.terminal = true; tui.via = "com.mitchellh.ghostty"; tui.now = "Running `bun test`"
        var scraper = Project(id: "scraper", name: "price-scraper", branch: "main", away: "12m", at: "11:52 AM",
                              headline: "You were retrying failed pages.",
                              context: "Failed pages now retry three times with backoff, and the run log lists the ones that never loaded.",
                              next: "Run it against the full catalogue", topic: "Retry failed pages with backoff", app: "pi",
                              agents: [AgentStatus(kind: .done, text: "pi finished", app: "pi")], steps: [])
        scraper.terminal = true; scraper.via = "com.mitchellh.ghostty"; scraper.host = "herdr"
        list += [tui, scraper]
        for (i, ago) in [(1, 2880.0), (2, 60), (3, 3 * 86_400), (4, 120), (5, 720)] { list[i].lastActive = now.addingTimeInterval(-ago) }
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
    /// Sessions at work lead their section and keep their places, newest begun first: each writes all the time, so by
    /// last activity two of them would trade places on every refresh.
    public static func ordered(_ list: [Project], _ query: String, now: Date, calendar: Calendar = .current) -> [Int] {
        let rank: (Int) -> Int = { [.needsYou: 0, .today: 1, .earlier: 2][section(list[$0], now: now, calendar: calendar)] ?? 2 }
        let working: (Int) -> Bool = { list[$0].status.kind == "running" }
        return shown(list, query).sorted { a, b in
            let ra = rank(a), rb = rank(b)
            if ra != rb { return ra < rb }
            let wa = working(a), wb = working(b)
            if wa != wb { return wa }
            if wa {
                let sa = list[a].startedAt ?? .distantPast, sb = list[b].startedAt ?? .distantPast
                return sa != sb ? sa > sb : list[a].id < list[b].id
            }
            let ta = list[a].lastActive ?? .distantPast, tb = list[b].lastActive ?? .distantPast
            return ta != tb ? ta > tb : a < b
        }
    }
}
