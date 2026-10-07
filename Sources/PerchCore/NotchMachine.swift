import Foundation

public enum NotchPhase: Equatable, Sendable { case idle, open, switcher, restoring, setup }

public enum NotchEvent: Equatable, Sendable {
    case comeBack, openSwitcher, next, previous, confirm, dismiss, timeout
    case choose(Int)
    case openSetup
    case back
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
            phase = .open
        case (.idle, .openSetup):
            phase = .setup
        case (.setup, .dismiss):
            close()
        case (.idle, .openSwitcher):
            guard projectCount > 0 else { return }
            phase = .switcher
        case (.open, .openSwitcher):
            phase = .switcher
        case (.switcher, .openSwitcher):
            close()
        case (.open, .next), (.switcher, .next):
            selected = (selected + 1) % projectCount
        case (.open, .previous), (.switcher, .previous):
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
        case (.open, .hoverChanged(let h)), (.switcher, .hoverChanged(let h)):
            hovering = h
        default:
            break
        }
    }

    private mutating func close() { phase = .idle; hovering = false }
}
