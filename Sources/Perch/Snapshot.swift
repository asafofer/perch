import Foundation
import PerchCore

/// What Swift tells the web UI. The UI never decides anything; it only draws this.
struct UISnapshot: Encodable {
    struct Screen: Encodable { let hasNotch: Bool; let notchW: CGFloat; let notchH: CGFloat }
    struct Status: Encodable { let kind: String; let text: String; let app: String }
    struct Step: Encodable { let icon: String; let text: String }
    /// What the agent is asking, for the card to answer: permission, question or plan.
    struct UIQuestion: Encodable { let text: String; let header: String; let multi: Bool; let options: [String]; let notes: [String] }
    struct UIAsk: Encodable { let kind: String; let title: String; let subject: String; let questions: [UIQuestion]; let answerable: Bool }
    struct UIProject: Encodable {
        let id, name: String
        let branch: String?
        let away, at, headline, context, next, topic, app: String
        let attention: Bool
        /// Changed since you last looked. Only then does a finished session glow green.
        let fresh: Bool
        /// What happened, measured against your break: "Finished 12m after you left".
        let line: String
        let status: Status
        let steps: [Step]
        let ask: UIAsk?
        /// While it works: the step it is on.
        let now: String?
    }

    struct Character: Encodable { let shape: String; let color: String }
    struct Source: Encodable { let id: String; let name: String; let count: Int; let names: [String]; let enabled: Bool }
    struct Onboarding: Encodable {
        let step: Int
        let total: Int
        let accessibility: Bool
        let summaries: String
        let scanning: Bool
        let sources: [Source]
        /// Only the character step, opened from Settings or the menu: no step count, and Done instead of Next.
        let only: Bool
        /// Perch's hook is in every enabled app: "on" or "off".
        let live: String
    }

    /// `live`: "on" when every enabled app has Perch's hook, "off" otherwise.
    struct Settings: Encodable { let sources: [Source]; let summaries: String; let accessibility: Bool; let idleMinutes: Int; let login: Bool; let live: String }

    let phase: String
    let settings: Settings?
    let character: Character
    let onboarding: Onboarding?
    let selected: Int
    let autoCollapse: Bool
    let timerToken: Int
    let screen: Screen
    let projects: [UIProject]
    /// Real app icons as data URLs. Sent once, with the first snapshot.
    let icons: [String: String]?
    let setup: String
    /// The session you are in right now. It never nudges you about itself.
    let activeId: String?
    /// The first scan is still running, so an empty list means "looking", not "nothing".
    let scanning: Bool
    /// Perch can type a reply for you (Accessibility). Without it, Reply copies and opens the session.
    let canSend: Bool

    init(machine: NotchMachine, projects: [Project], screen: ScreenInfo, timerToken: Int, icons: [String: String]? = nil, setup: String = "ready", allowAutoCollapse: Bool = true, activeId: String? = nil, scanning: Bool = false, canSend: Bool = true, fresh: Set<String> = [], lines: [String: String] = [:], onboarding: Onboarding? = nil, settings: Settings? = nil) {
        self.onboarding = onboarding; self.settings = settings
        character = Character(shape: Prefs.shape, color: Prefs.color)
        self.icons = icons; self.setup = setup; self.activeId = activeId; self.scanning = scanning; self.canSend = canSend
        phase = switch machine.phase { case .idle: "idle"; case .open: "open"; case .switcher: "switcher"; case .restoring: "restoring"; case .setup: "setup"; case .onboarding: "onboarding"; case .settings: "settings" }
        selected = machine.selected
        autoCollapse = machine.autoCollapses && allowAutoCollapse
        self.timerToken = timerToken
        self.screen = Screen(hasNotch: screen.notchSize != nil, notchW: screen.notchSize?.width ?? 0, notchH: screen.notchSize?.height ?? NotchGeometry.idleSize(for: screen).height)
        self.projects = projects.map { p in
            UIProject(id: p.id, name: p.name, branch: p.branch, away: p.away, at: p.at, headline: p.headline,
                      context: p.context, next: p.next, topic: p.topic, app: p.app, attention: p.needsAttention,
                      fresh: fresh.contains(p.id), line: lines[p.id] ?? "",
                      status: Status(kind: p.status.kind, text: p.status.text, app: p.status.app),
                      steps: p.steps.map { Step(icon: $0.icon, text: $0.text) },
                      ask: p.ask.map { UIAsk(kind: $0.kind.rawValue, title: $0.title, subject: $0.subject,
                                                 questions: $0.questions.map { UIQuestion(text: $0.text, header: $0.header, multi: $0.multiSelect, options: $0.options, notes: $0.notes) },
                                                 answerable: $0.answerable) },
                      now: p.now)
        }
    }
}
