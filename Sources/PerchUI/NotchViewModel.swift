import SwiftUI
import PerchCore

@MainActor @Observable
public final class NotchViewModel {
    public private(set) var machine: NotchMachine
    public var projects: [Project]
    public var screen: ScreenInfo
    /// 1 -> 0 over the auto-collapse window; drives the thin timer line.
    public var barProgress: CGFloat = 1
    public var hopCount = 0
    /// Called after every phase change with (old, new). The controller hangs timers and haptics here.
    public var onPhaseChange: ((NotchPhase, NotchPhase) -> Void)?

    public init(projects: [Project], screen: ScreenInfo) {
        self.projects = projects
        self.screen = screen
        self.machine = NotchMachine(projectCount: projects.count)
    }

    public var phase: NotchPhase { machine.phase }
    public var selected: Int { machine.selected }
    public var project: Project? { projects.indices.contains(selected) ? projects[selected] : nil }
    public var hasNotch: Bool { screen.notchSize != nil }
    public var bodySize: CGSize { NotchGeometry.size(for: phase, screen: screen) }
    public var panelSize: CGSize { NotchGeometry.panelFrame(for: screen).size }

    public var creatureMood: Creature.Mood {
        switch phase {
        case .idle: .sleep
        case .open, .switcher: .awake
        case .restoring: .happy
        }
    }

    public func send(_ event: NotchEvent) {
        let old = machine.phase
        let animation: Animation = switch (old, event) {
        case (.idle, _): Motion.expand
        case (_, .dismiss), (_, .timeout), (_, .restoreFinished): Motion.collapse
        case (.open, .openSwitcher), (.switcher, .openSwitcher): Motion.expand
        default: Motion.snappy
        }
        withAnimation(animation) { machine.send(event) }
        if machine.phase != old {
            if machine.phase == .restoring { hopCount += 1 }
            onPhaseChange?(old, machine.phase)
        }
    }

    /// Jump straight to a project and confirm it (a click on a switcher row).
    public func choose(_ index: Int) {
        while machine.selected != index { send(.next) }
        send(.confirm)
    }

    /// Snapshot/testing helper: set a phase without animation.
    public func force(phase target: NotchPhase, selected index: Int = 0) {
        var m = NotchMachine(projectCount: projects.count)
        switch target {
        case .idle: break
        case .open: m.send(.comeBack)
        case .switcher: m.send(.openSwitcher)
        case .restoring: m.send(.comeBack); m.send(.confirm)
        }
        for _ in 0..<index { m.send(.next) }
        machine = m
    }
}
