import Foundation
import PerchCore

/// What Swift tells the web UI. The UI never decides anything; it only draws this.
struct UISnapshot: Encodable {
    struct Screen: Encodable { let hasNotch: Bool; let notchW: CGFloat; let notchH: CGFloat }
    struct Status: Encodable { let kind: String; let text: String; let app: String }
    struct Step: Encodable { let icon: String; let text: String }
    struct UIProject: Encodable {
        let id, name: String
        let branch: String?
        let away, at, headline, context, next, topic, app: String
        let attention: Bool
        let status: Status
        let steps: [Step]
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
    }

    let phase: String
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

    init(machine: NotchMachine, projects: [Project], screen: ScreenInfo, timerToken: Int, icons: [String: String]? = nil, setup: String = "ready", allowAutoCollapse: Bool = true, activeId: String? = nil, onboarding: Onboarding? = nil) {
        self.onboarding = onboarding
        character = Character(shape: Prefs.shape, color: Prefs.color)
        self.icons = icons; self.setup = setup; self.activeId = activeId
        phase = switch machine.phase { case .idle: "idle"; case .open: "open"; case .switcher: "switcher"; case .restoring: "restoring"; case .setup: "setup"; case .onboarding: "onboarding" }
        selected = machine.selected
        autoCollapse = machine.autoCollapses && allowAutoCollapse
        self.timerToken = timerToken
        self.screen = Screen(hasNotch: screen.notchSize != nil, notchW: screen.notchSize?.width ?? 0, notchH: screen.notchSize?.height ?? 32)
        self.projects = projects.map { p in
            UIProject(id: p.id, name: p.name, branch: p.branch, away: p.away, at: p.at, headline: p.headline,
                      context: p.context, next: p.next, topic: p.topic, app: p.app, attention: p.needsAttention,
                      status: Status(kind: p.status.kind, text: p.status.text, app: p.status.app),
                      steps: p.steps.map { Step(icon: $0.icon, text: $0.text) })
        }
    }
}
