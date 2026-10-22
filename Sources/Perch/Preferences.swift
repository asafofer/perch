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
    /// One that starts off (`Agent.onByDefault`: Claude chats) is kept the other way round, as switched on.
    static var enabledSources: Set<String> {
        get {
            let all = Set(Agent.all.filter(\.onByDefault).map(\.id)).union(d.stringArray(forKey: "sources.optedIn") ?? [])
            if let off = d.array(forKey: "sources.disabled") as? [String] { return all.subtracting(off) }
            if let on = d.array(forKey: "sources.enabled") as? [String] { return all.subtracting(Set(["claude", "codex"]).subtracting(on)) }
            return all
        }
        set {
            let byDefault = Set(Agent.all.filter(\.onByDefault).map(\.id))
            d.set(Array(byDefault.subtracting(newValue)), forKey: "sources.disabled")
            d.set(Array(newValue.subtracting(byDefault)), forKey: "sources.optedIn")
        }
    }
    /// Accessibility Perch had (AccessLoss): whether it ever had it, the build that last had it (a loss on another build came
    /// with an update), and whether this loss was said, so a relaunch does not say it again.
    /// nil on an install from before it was kept (AccessLoss.seeded).
    static var accessHad: Bool? { get { d.object(forKey: "access.had") as? Bool } set { d.set(newValue, forKey: "access.had") } }
    static var accessHadOn: String? { get { d.string(forKey: "access.hadOn") } set { d.set(newValue, forKey: "access.hadOn") } }
    static var accessSaid: Bool { get { d.bool(forKey: "access.said") } set { d.set(newValue, forKey: "access.said") } }
    /// The agent and folder you last started a new session with (NewSession.Choice id, folder path).
    static var lastNewChoice: String? { get { d.string(forKey: "new.choice") } set { d.set(newValue, forKey: "new.choice") } }
    static var lastNewFolder: String? { get { d.string(forKey: "new.folder") } set { d.set(newValue, forKey: "new.folder") } }
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
    /// Seconds an unanswered question stays in the notch as wings, after its first nine in full. 60 by default.
    static var questionSeconds: Int {
        get { let v = d.integer(forKey: "questionSeconds"); return [30, 60, 300].contains(v) ? v : 60 }
        set { d.set(newValue, forKey: "questionSeconds") }
    }
    /// Whether resting the cursor on the top edge of a display without a notch opens Perch there. Off by default: such a
    /// display shows nothing at rest, and the hotkey and the live activity still work on it.
    static var hoverExternal: Bool {
        get { d.bool(forKey: "hoverExternal") }
        set { d.set(newValue, forKey: "hoverExternal") }
    }
    /// Where the shortcut opens Perch and where it shows up by itself (Show Perch on): the screen with the mouse by default.
    static var showOn: ShowOn {
        get { ShowOn(raw: d.string(forKey: "showOn") ?? "") }
        set { d.set(newValue.raw, forKey: "showOn") }
    }
    /// The chosen display's name, so Settings can still name it while it is not connected.
    static var showOnName: String? {
        get { d.string(forKey: "showOnName") }
        set { if let v = newValue { d.set(v, forKey: "showOnName") } else { d.removeObject(forKey: "showOnName") } }
    }
    /// The kinds of live activity switched off in Settings (Notify me about), as `NotifyKind` names. Empty by default: the notch announces everything.
    static var notifyOff: Set<String> {
        get { NotifyKinds.off(from: d.stringArray(forKey: "notifyOff") ?? []) }
        set { d.set(newValue.sorted(), forKey: "notifyOff") }
    }
    /// What opens and closes Perch: a tap of Command and Option unless you recorded your own.
    static var openShortcut: Shortcut {
        get { (d.data(forKey: "shortcut.open").flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) }).flatMap { Shortcut.problem($0) == nil ? $0 : nil } ?? .standard }
        set { if newValue.isStandard { d.removeObject(forKey: "shortcut.open") } else if let data = try? JSONEncoder().encode(newValue) { d.set(data, forKey: "shortcut.open") } }
    }
    /// What starts a new session from anywhere: Option+Command+N unless you recorded your own. Always a key combo.
    static let standardNew = Shortcut.combo([.option, .command], keyCode: 45, name: "N")
    static var newShortcut: Shortcut {
        get { (d.data(forKey: "shortcut.new").flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) }).flatMap { $0.kind == .combo && Shortcut.problem($0) == nil ? $0 : nil } ?? standardNew }
        set { if newValue == standardNew { d.removeObject(forKey: "shortcut.new") } else if let data = try? JSONEncoder().encode(newValue) { d.set(data, forKey: "shortcut.new") } }
    }
    /// Minutes away before the welcome card comes back. 20 by default.
    static var idleMinutes: Int {
        get { let v = d.integer(forKey: "idleMinutes"); return v > 0 ? v : 20 }
        set { d.set(newValue, forKey: "idleMinutes") }
    }
}
