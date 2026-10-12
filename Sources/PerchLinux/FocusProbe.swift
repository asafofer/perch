import CPerchLinux
import Foundation
import PerchCore

// OWNER: the processes-and-terminals agent. STUB.
// What is in front, for "the session you are in": the active X window's app, and which Spot (tty, herdr pane, tmux
// pane) it shows. Readings are taken a second apart; one older than maxAge is not trusted.
@MainActor
final class FocusProbe {
    struct Reading {
        let app: String
        let at: Date
        let looking: Looking
    }
    private(set) var reading: Reading?
    /// A new reading differs from the last one.
    var changed: (() -> Void)?
    static let maxAge: TimeInterval = 5

    /// Whether Perch can read what this app shows.
    static func reads(_ app: String) -> Bool { false }
    nonisolated static func setKnown(_ v: (hits: [LiveSessions.Hit], viewers: [LiveSessions.Viewer])) {}
    func fresh(for app: String) -> Reading? { nil }
    func tick(app: String) {}
    func poll(app: String) {}
}

/// The app in front: the active window's app id, else nil.
enum FrontApp {
    static func id() -> String? { X11.activeWindow().flatMap(X11.appId) }
}
