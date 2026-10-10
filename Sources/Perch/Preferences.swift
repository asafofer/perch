import Foundation
import PerchCore

/// What Perch remembers between launches.
enum Prefs {
    private static let d = UserDefaults.standard
    static var onboarded: Bool { get { d.bool(forKey: "onboarded") } set { d.set(newValue, forKey: "onboarded") } }
    /// Set when Perch restarts itself in the middle of setup, so it picks up at the same step.
    static var resumeStep: Int? {
        get { d.object(forKey: "resumeStep") as? Int }
        set { if let v = newValue { d.set(v, forKey: "resumeStep") } else { d.removeObject(forKey: "resumeStep") } }
    }
    static var shape: String { get { d.string(forKey: "character.shape") ?? "ears" } set { d.set(newValue, forKey: "character.shape") } }
    static var color: String { get { d.string(forKey: "character.color") ?? "#F5B83D" } set { d.set(newValue, forKey: "character.color") } }
    /// Which agents Perch reads: all of them, except the ones you switched off. Kept as the ones switched off, so an agent
    /// Perch learns later starts on. (Before, the ones switched on were kept, when there were only Claude and Codex.)
    static var enabledSources: Set<String> {
        get {
            let all = Set(Agent.all.map(\.id))
            if let off = d.array(forKey: "sources.disabled") as? [String] { return all.subtracting(off) }
            if let on = d.array(forKey: "sources.enabled") as? [String] { return all.subtracting(Set(["claude", "codex"]).subtracting(on)) }
            return all
        }
        set { d.set(Array(Set(Agent.all.map(\.id)).subtracting(newValue)), forKey: "sources.disabled") }
    }
    /// The terminal app you used most recently, so Pick up opens a closed terminal session there.
    static var lastTerminal: String? { get { d.string(forKey: "terminal.last") } set { d.set(newValue, forKey: "terminal.last") } }
    /// Where each terminal session last ran, by session id: {"kind": "herdr", "socket", "session", "workspace", "bin"} or
    /// {"kind": "cmux"}. A session that stopped reopens there.
    static var places: [String: [String: String]] {
        get { d.dictionary(forKey: "places") as? [String: [String: String]] ?? [:] }
        set { d.set(newValue, forKey: "places") }
    }
    /// When you last saw each session's latest activity (session id to time). Perch speaks up only about what changed since.
    static var seen: [String: Double] { get { d.dictionary(forKey: "seen") as? [String: Double] ?? [:] } set { d.set(newValue, forKey: "seen") } }
    /// Set once the sessions that existed before Perch was installed have been marked as seen.
    static var seenBaselined: Bool { get { d.bool(forKey: "seen.baselined") } set { d.set(newValue, forKey: "seen.baselined") } }
    /// Minutes away before the welcome card comes back. 20 by default.
    static var idleMinutes: Int {
        get { let v = d.integer(forKey: "idleMinutes"); return v > 0 ? v : 20 }
        set { d.set(newValue, forKey: "idleMinutes") }
    }
}
