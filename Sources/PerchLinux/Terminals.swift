import CPerchLinux
import Foundation
import PerchCore

// OWNER: the processes-and-terminals agent. STUB: signatures are the contract the controller calls; keep them.
// Linux's Terminals.swift: running agents from /proc (LiveSessions), going back to them, typing into them, opening a
// new terminal. Apps are named by their windows' WM_CLASS, lowercased (X11.appId), where the Mac uses bundle ids.

enum Terminals {
    /// Every app that counts as a terminal (WM_CLASS, lowercased), with the name its icon goes by in the page.
    static let keys: [String: String] = [:]
    /// The terminals Perch can open a new session in.
    static let opens: Set<String> = []
    /// The terminal you used last, if Perch can open a session in it; else the first one installed.
    static var preferred: String { Prefs.lastTerminal ?? "xterm" }
    /// Opens a new window in `cwd` running `command`.
    static func open(_ command: String, in cwd: String, app: String = preferred) {}
    /// Brings a running agent forward: its herdr pane, tmux pane, or terminal window. The app id brought forward, or nil.
    static func focus(_ live: LiveSessions.Hit, hints: [String] = []) -> String? { nil }
    /// Brings forward the terminal showing a herdr client.
    static func show(_ v: LiveSessions.Viewer) -> String? { nil }
    /// Types a line into a running agent and presses Return. False when it could not be typed into.
    static func type(_ line: String, into live: LiveSessions.Hit) -> Bool { false }
    static func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}

/// Coding agents running right now, from /proc and their own environment.
enum LiveSessions {
    struct Hit: Equatable {
        let pid: pid_t, cwd: String, tty: String
        /// An Agent id.
        let agent: String
        /// The terminal app it shows in (an app id). For herdr, the terminal that shows a client of its server.
        let app: String?
        let place: Place
        let argv: [String]
        let started: Date
        let viewer: Viewer?
        let herdrBin: String?
    }
    struct Viewer: Equatable { let pid: pid_t; let tty: String; let cwd: String; let app: String?; let place: Place; let session: String }

    static func all() -> [Hit] { scan().hits }
    static func scan() -> (hits: [Hit], viewers: [Viewer]) { ([], []) }
}
