import Foundation

public enum NotchPhase: Equatable, Sendable { case idle, open, switcher, restoring, onboarding, settings, whatsNew, newSession }

public enum NotchEvent: Equatable, Sendable {
    case comeBack, openSwitcher, next, previous, confirm, dismiss, timeout
    case choose(Int)
    /// From the list: that session's card, without opening it.
    case show(Int)
    /// From the list: the pointer came onto a row, which is now the one the arrows and Return act on.
    case select(Int)
    case openOnboarding
    /// The first start after an update: the card that says what is new. Confirm (Got it) goes on to the list.
    case openWhatsNew
    case openSettings
    /// A new session (Command+Option+N, or New session in the list).
    case openNew
    /// The new session was started: back to the list it was opened from, else closed.
    case started
    case back
    /// The list was refreshed while the card is up: keep the card, clamp what is selected.
    case projectsChanged(count: Int, selected: Int)
    case hoverChanged(Bool), restoreFinished
    /// Command+Option soon after you put it away: straight back to that card, or to the list on that row (nil: its top row).
    case reopen(NotchPhase, selected: Int?)
}

/// What showed when you put Perch away (Esc, a click elsewhere, Command+Option, the card folding away), so Command+Option
/// brings it back: that session's card, or the list with its filter on the same row, and a reply you had open. It keeps
/// five minutes, and a card only while its session is still listed. Done with it (Pick up, a reply sent, an answer,
/// Not now) and there is nothing to bring back: Command+Option opens the list.
public struct PutAway: Equatable, Sendable {
    public let phase: NotchPhase
    /// The session on the card, or the row the list was on.
    public let session: String?
    /// What was typed in the list.
    public let query: String
    /// The card's reply field was open.
    public let replying: Bool
    public let at: Date

    public static let keeps: TimeInterval = 5 * 60

    /// Only the card and the list come back, and a card only with its session.
    public init?(phase: NotchPhase, session: String?, query: String = "", replying: Bool = false, at: Date) {
        guard phase == .switcher || (phase == .open && session != nil) else { return nil }
        self.phase = phase; self.session = session; self.at = at
        self.query = phase == .switcher ? query : ""
        self.replying = phase == .open && replying
    }

    /// Where to go back to among the sessions listed now (`ids`, in the machine's order). Nil once it is too old, or
    /// when the card's session has gone; a list always comes back on its top row.
    public func recall(ids: [String], now: Date) -> NotchEvent? {
        guard now.timeIntervalSince(at) < Self.keeps, now >= at.addingTimeInterval(-1) else { return nil }
        let row = session.flatMap { ids.firstIndex(of: $0) }
        if phase == .open { return row.map { .reopen(.open, selected: $0) } }
        return .reopen(.switcher, selected: nil)   // the list comes back with its filter, lit on its top row
    }
}

/// Pure state machine for the notch. No UI, no timers.
public struct NotchMachine: Equatable, Sendable {
    public private(set) var phase: NotchPhase = .idle
    /// The card or list Settings was opened from: Back (Esc) returns there. Nil when it came from the menu bar or a shortcut.
    public private(set) var settingsFrom: NotchPhase?
    /// Where a new session was opened from: the list or a card (Esc goes back there, and the list is where it lands), or nil.
    public private(set) var newFrom: NotchPhase?
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
        case (.switcher, .select(let i)):
            guard (0..<projectCount).contains(i) else { return }
            selected = i
        case (.idle, .openSettings), (.open, .openSettings), (.switcher, .openSettings):
            settingsFrom = phase == .idle ? nil : phase
            phase = .settings
        case (.idle, .openNew), (.open, .openNew), (.switcher, .openNew):
            newFrom = phase == .idle ? nil : phase
            phase = .newSession
        case (.newSession, .back):
            if let from = newFrom, from != .open || projectCount > 0 { phase = from } else { close() }
        case (.newSession, .started):
            if newFrom == .switcher { phase = .switcher } else { close() }
        case (.newSession, .dismiss):
            close()
        case (.settings, .back):
            if let from = settingsFrom { phase = from } else { close() }
        case (.settings, .dismiss):
            close()
        case (.onboarding, .dismiss):
            close()
        case (.idle, .openWhatsNew):
            selected = 0; phase = .whatsNew
        case (.whatsNew, .confirm):
            phase = .switcher
        case (.whatsNew, .dismiss):
            close()
        case (.whatsNew, .openSwitcher):
            phase = .switcher   // the shortcut that opens Perch goes on to the list too
        case (.idle, .openOnboarding), (.settings, .openOnboarding):
            phase = .onboarding
        case (.onboarding, .openSettings):
            phase = .settings   // back from changing the character
        case (.idle, .reopen(.open, let i?)):
            guard (0..<projectCount).contains(i) else { return }
            selected = i; phase = .open
        case (.idle, .reopen(.switcher, let i)):
            selected = i.map { min(max($0, 0), max(projectCount - 1, 0)) } ?? 0
            phase = .switcher
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

    private mutating func close() { phase = .idle; hovering = false; settingsFrom = nil; newFrom = nil }
}
