import CPerchLinux
import Foundation
import PerchCore

// OWNER: the sessions agent. STUB.
/// The real icons of the apps the page talks about, from the icon theme, as data URLs keyed like the Mac's
/// ("terminal", "kitty", "opencode" ... and every value in Terminals.keys).
enum AppIcons {
    static func knows(_ key: String) -> Bool { false }
    static func all() -> [String: String] { [:] }
}

/// Whether an agent is on this machine: its command or the folder it keeps sessions in.
enum AgentPresence {
    static func installed(_ a: Agent) -> Bool { false }
}
