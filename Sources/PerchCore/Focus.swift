import Foundation

/// Which running session you are in, as far as Perch can tell. A session you are in never gets the live activity or a
/// nudge, so a wrong answer is worse in one direction: when Perch cannot tell which tab, pane or surface is in front,
/// every live session in that app counts as "maybe" and stays quiet.
public enum Spot {
    /// Where a running agent lives, as a key to compare with what is in front: its herdr or tmux pane (on that server), its
    /// cmux surface, its agterm pane, or its terminal's tty.
    public static func key(_ place: Place, tty: String) -> String {
        switch place {
        case .herdr(let pane, let socket, _): return herdr(socket: socket, pane: pane)
        case .tmux(let pane, let socket): return tmux(socket: socket, pane: pane)
        case .cmux(_, let surface): return cmux(surface: surface)
        case .agterm(_, _, let pane): return agterm(pane: pane)
        case .tab: return Self.tty(tty)
        }
    }
    public static func cmux(surface: String) -> String { "cmux:" + surface.lowercased() }
    public static func agterm(pane: String) -> String { "agterm:" + pane.lowercased() }
    public static func tty(_ tty: String) -> String { "tty:" + tty }
    public static func herdr(socket: String, pane: String) -> String { herdrPrefix(socket) + pane }
    static func herdrPrefix(_ socket: String) -> String { "herdr:\(socket)|" }
    public static func tmux(socket: String, pane: String) -> String { "tmux:\(socket)|" + pane }
}

/// What was read from the app in front.
public struct Looking: Equatable, Sendable {
    /// The `Spot` keys in front now (the focused tab, surface or pane).
    public var spots: Set<String>
    /// herdr servers whose focused pane could not be told (several clients attached): all their panes count as maybe.
    public var servers: Set<String>
    /// Nothing could be read: every live session in that app counts as maybe.
    public var unknown: Bool
    public init(spots: Set<String> = [], servers: Set<String> = [], unknown: Bool = false) { self.spots = spots; self.servers = servers; self.unknown = unknown }
    public static let cannotTell = Looking(unknown: true)
}

public enum Focus {
    /// The live terminal sessions shown in `app` that you are in (`sure`) or may be in (`maybe`, a superset of `sure`).
    /// A session that is not running has no spot, so it is never in.
    public static func inTerminal(_ projects: [Project], app: String, looking: Looking) -> (sure: Set<String>, maybe: Set<String>) {
        var sure = Set<String>(), maybe = Set<String>()
        for p in projects where p.terminal && p.via == app {
            guard let spot = p.spot else { continue }
            if looking.unknown { maybe.insert(p.id); continue }
            if looking.spots.contains(spot) { sure.insert(p.id); maybe.insert(p.id) }
            else if looking.servers.contains(where: { spot.hasPrefix(Spot.herdrPrefix($0)) }) { maybe.insert(p.id) }
        }
        return (sure, maybe)
    }

    /// The Codex app has no way to tell its open thread: any of its threads may be the one in front.
    public static func inCodexApp(_ projects: [Project]) -> Set<String> {
        Set(projects.filter { $0.app == "codex" && !$0.terminal }.map(\.id))
    }
}
