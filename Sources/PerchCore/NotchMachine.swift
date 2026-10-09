import Foundation

public enum NotchPhase: Equatable, Sendable { case idle, open, switcher, restoring, setup, onboarding, settings }

public enum NotchEvent: Equatable, Sendable {
    case comeBack, openSwitcher, next, previous, confirm, dismiss, timeout
    case choose(Int)
    /// From the list: that session's card, without opening it.
    case show(Int)
    case openSetup
    case openOnboarding
    case openSettings
    case back
    /// The list was refreshed while the card is up: keep the card, clamp what is selected.
    case projectsChanged(count: Int, selected: Int)
    case hoverChanged(Bool), restoreFinished
}

/// Pure state machine for the notch. No UI, no timers.
public struct NotchMachine: Equatable, Sendable {
    public private(set) var phase: NotchPhase = .idle
    public private(set) var selected = 0
    public private(set) var hovering = false
    public var projectCount: Int

    public init(projectCount: Int) { self.projectCount = projectCount }

    /// True while the card should count down to auto-collapse.
    public var autoCollapses: Bool { phase == .open && !hovering }

    public mutating func send(_ event: NotchEvent) {
        switch (phase, event) {
        case (.idle, .comeBack):
            guard projectCount > 0 else { return }   // nothing to say: stay closed
            selected = 0; phase = .open
        case (.switcher, .back):
            guard projectCount > 0 else { return }   // no card to go back to
            phase = .open
        case (.switcher, .show(let i)):
            guard (0..<projectCount).contains(i) else { return }
            selected = i; phase = .open
        case (.idle, .openSetup):
            phase = .setup
        case (.idle, .openSettings), (.open, .openSettings), (.switcher, .openSettings):
            phase = .settings
        case (.settings, .dismiss):
            close()
        case (.setup, .dismiss), (.onboarding, .dismiss):
            close()
        case (.idle, .openOnboarding), (.settings, .openOnboarding):
            phase = .onboarding
        case (.onboarding, .openSettings):
            phase = .settings   // back from changing the character
        case (.idle, .openSwitcher):
            phase = .switcher   // asked for: an empty list says so instead of doing nothing
        case (.open, .openSwitcher):
            phase = .switcher
        case (.switcher, .openSwitcher):
            close()
        case (.open, .next), (.switcher, .next):
            guard projectCount > 0 else { return }
            selected = (selected + 1) % projectCount
        case (.open, .previous), (.switcher, .previous):
            guard projectCount > 0 else { return }
            selected = (selected - 1 + projectCount) % projectCount
        case (.open, .confirm), (.switcher, .confirm):
            phase = .restoring
        case (.open, .choose(let i)), (.switcher, .choose(let i)):
            guard (0..<projectCount).contains(i) else { return }
            selected = i; phase = .restoring
        case (.open, .dismiss), (.switcher, .dismiss), (.restoring, .dismiss):
            close()
        case (.open, .timeout):
            if !hovering { close() }
        case (.restoring, .restoreFinished):
            close()
        case (.open, .projectsChanged(let n, let sel)), (.switcher, .projectsChanged(let n, let sel)):
            projectCount = n
            if n == 0 { if phase == .open { close() } else { selected = 0 } } else { selected = min(max(sel, 0), n - 1) }
        case (_, .projectsChanged(let n, _)):
            projectCount = n
        case (.open, .hoverChanged(let h)), (.switcher, .hoverChanged(let h)):
            hovering = h
        default:
            break
        }
    }

    private mutating func close() { phase = .idle; hovering = false }
}
