import Foundation

/// The moments the notch can announce as live activity (Settings, Notify me about). Turning one off only stops the notch
/// from speaking about it: the list, the cards, the status rings and the welcome card still say everything.
/// The page decides which kind a session is in (app.js `notifyKind`); these are the names it and Swift share.
public enum NotifyKind: String, CaseIterable, Sendable {
    case done, run, ask, plan, error
}

public enum NotifyKinds {
    /// The kinds that are switched off, from what was stored or sent: only names Perch knows, so a stale or garbled value
    /// can never silence a kind it does not name.
    public static func off(from raw: [String]) -> Set<String> {
        Set(raw.filter { NotifyKind(rawValue: $0) != nil })
    }

    /// `off` after switching `kind` on or off. An unknown kind changes nothing.
    public static func toggled(_ off: Set<String>, kind: String, enabled: Bool) -> Set<String> {
        guard NotifyKind(rawValue: kind) != nil else { return off }
        var set = off
        if enabled { set.remove(kind) } else { set.insert(kind) }
        return set
    }
}
