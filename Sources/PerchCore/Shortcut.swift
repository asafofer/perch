import Foundation


/// The shortcut that opens and closes Perch: a tap of two or more modifier keys (the default, Command+Option), or a key
/// with modifiers. Pure data and rules, no AppKit: the app turns key events into `ShortcutRecorder` calls.
public struct ShortcutMods: OptionSet, Equatable, Hashable, Sendable, Codable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let control = ShortcutMods(rawValue: 1)
    public static let option = ShortcutMods(rawValue: 2)
    public static let shift = ShortcutMods(rawValue: 4)
    public static let command = ShortcutMods(rawValue: 8)

    /// Glyphs in the order macOS writes them.
    public var glyphs: [String] {
        [(ShortcutMods.control, "\u{2303}"), (.option, "\u{2325}"), (.shift, "\u{21E7}"), (.command, "\u{2318}")].filter { contains($0.0) }.map(\.1)
    }
    public var count: Int { glyphs.count }
}

public struct Shortcut: Equatable, Sendable, Codable {
    public enum Kind: String, Sendable, Codable { case tap, combo }
    public var kind: Kind
    public var mods: ShortcutMods
    /// Combo only: the key's code and what to call it.
    public var keyCode: Int?
    public var keyName: String?

    public static let standard = Shortcut(kind: .tap, mods: [.command, .option], keyCode: nil, keyName: nil)
    public static func tap(_ mods: ShortcutMods) -> Shortcut { Shortcut(kind: .tap, mods: mods, keyCode: nil, keyName: nil) }
    public static func combo(_ mods: ShortcutMods, keyCode: Int, name: String) -> Shortcut { Shortcut(kind: .combo, mods: mods, keyCode: keyCode, keyName: name) }

    public var isStandard: Bool { self == .standard }
    /// One entry per key cap, for drawing: the modifiers, then the key.
    public var keys: [String] { mods.glyphs + (keyName.map { [$0] } ?? []) }
    /// "\u{2318}\u{2325}" or "\u{2303}Space".
    public var label: String { keys.joined() }

    // MARK: rules

    /// Why a shortcut cannot be used, or nil when it can.
    public static func problem(_ s: Shortcut) -> String? {
        switch s.kind {
        case .tap:
            return s.mods.count < 2 ? "A tap needs two or more modifier keys" : nil
        case .combo:
            guard let code = s.keyCode else { return "Press a key too" }
            if s.mods.isDisjoint(with: [.control, .option, .command]) { return "Hold \u{2318}, \u{2325} or \u{2303} too" }
            if let own = taken[Taken(mods: s.mods, keyCode: code)] { return "\(s.label) is \(own)" }
            return nil
        }
    }

    private struct Taken: Hashable { let mods: ShortcutMods; let keyCode: Int }
    /// Perch's own keys for the welcome card, the list and Quit, and Settings on the card. On Linux, Control and Alt belong to
    /// the desktop (Ctrl+Alt+L locks the screen), so these sit with Perch's other keys under Super and Alt, and Settings is
    /// Ctrl+comma as Linux apps have it.
    #if os(Linux)
    public static let ownMods: ShortcutMods = [.command, .option]
    private static let settingsMods: ShortcutMods = .control
    #else
    public static let ownMods: ShortcutMods = [.control, .option]
    private static let settingsMods: ShortcutMods = .command
    #endif
    private static let taken: [Taken: String] = {
        var t: [Taken: String] = [
            Taken(mods: ownMods, keyCode: 35): "the welcome card",
            Taken(mods: ownMods, keyCode: 37): "the project list",
            Taken(mods: ownMods, keyCode: 12): "Quit Perch",
            Taken(mods: .command, keyCode: 15): "Reply in Perch",
            Taken(mods: settingsMods, keyCode: 43): "Settings in Perch",
        ]
        // The notch's own buttons while it asks something: Allow, Deny, Reply, put away, choices, open.
        for code in [16, 45, 15, 47, 18, 19, 20, 36] { t[Taken(mods: [.command, .option], keyCode: code)] = "a button in the notch" }
        // What every Mac app does.
        for (code, what) in [(12, "Quit in every app"), (13, "Close in every app"), (8, "Copy"), (9, "Paste"), (7, "Cut"), (0, "Select all"), (6, "Undo"),
                             (4, "Hide in every app"), (46, "Minimize in every app"), (48, "Switch apps"), (49, "Spotlight"), (50, "Switch windows")] {
            t[Taken(mods: .command, keyCode: code)] = what
        }
        return t
    }()

    /// What a key is called on a key cap: special keys by code, others by what they type (a US-position letter on a layout
    /// without Latin ones).
    public static func name(keyCode: Int, typed: String?) -> String {
        let special: [Int: String] = [49: "Space", 36: "Return", 76: "Enter", 48: "Tab", 51: "Delete", 117: "Forward delete", 115: "Home", 119: "End", 116: "Page up", 121: "Page down",
                                      123: "\u{2190}", 124: "\u{2192}", 125: "\u{2193}", 126: "\u{2191}",
                                      122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"]
        if let s = special[keyCode] { return s }
        return KeyLayout.shortcut(typed: typed, keyCode: UInt16(clamping: keyCode)).uppercased()
    }
}

/// Listens for the next shortcut while you press it: hold modifiers and let go (a tap), or press modifiers and a key (a
/// combo). What you press is only a choice: pressing again replaces it, and Return alone saves it. Esc stops. Anything Perch
/// cannot use says why and the recorder keeps listening.
public struct ShortcutRecorder: Sendable {
    public enum Outcome: Equatable, Sendable { case none, cancel
        /// A usable shortcut was pressed. It is not saved yet: the recorder keeps listening and Return saves it.
        case chosen(Shortcut)
        /// Return saved the chosen shortcut.
        case record(Shortcut)
        /// Why it cannot be used, and the keys that were pressed, so the card can still show what you did.
        case refused(String, keys: [String]) }

    private var peak: ShortcutMods = []
    private var keyPressed = false
    /// The modifiers held now: a press is fresh only when they go up from none.
    private var held: ShortcutMods = []
    /// The last usable shortcut pressed, waiting for Return.
    public private(set) var pending: Shortcut?
    public init() {}

    /// A key went down with these modifiers held.
    public mutating func keyDown(keyCode: Int, typed: String?, mods: ShortcutMods) -> Outcome {
        keyPressed = true; held = mods
        if keyCode == 53 { return .cancel }
        if [36, 76].contains(keyCode), mods.isEmpty, let chosen = pending { return .record(chosen) }
        let s = Shortcut.combo(mods, keyCode: keyCode, name: Shortcut.name(keyCode: keyCode, typed: typed))
        if let why = Shortcut.problem(s) { return .refused(why, keys: s.keys) }
        peak = []; pending = s
        return .chosen(s)
    }

    /// The modifiers held changed. A tap is recorded when they are all let go with no key pressed in between.
    public mutating func flagsChanged(mods: ShortcutMods) -> Outcome {
        let fresh = held.isEmpty
        held = mods
        if !mods.isEmpty {
            // A fresh press: a key refused a moment ago does not count against it. Letting go of one modifier of a combo
            // just chosen (Option before Control) is not a fresh press, so the rest coming up is not a tap.
            if fresh { keyPressed = false; peak = [] }
            if mods.count >= peak.count { peak = mods }
            return .none
        }
        defer { peak = []; keyPressed = false }
        guard !keyPressed, !peak.isEmpty else { return .none }
        let s = Shortcut.tap(peak)
        if let why = Shortcut.problem(s) { return .refused(why, keys: s.keys) }
        pending = s
        return .chosen(s)
    }
}

/// Watches the modifiers for a tap of the open shortcut. A tap is the shortcut's modifiers pressed from nothing and let go
/// within 0.6 s, with no other modifier and no key at any point in that press. Another app's shortcut that shares the
/// modifiers (Command+Option+Shift+L) is not a tap: letting go of Shift and L first leaves Command+Option held, and a key
/// another app's hotkey takes never reaches Perch as an event, so the system's count of key presses (`keyDowns`) is
/// compared instead.
public struct ModifierTap: Sendable {
    public var mods: ShortcutMods
    private var held: ShortcutMods = []
    private var start: Date?
    private var startKeyDowns = 0
    private var dirty = false
    public init(_ mods: ShortcutMods) { self.mods = mods }

    /// A key went down while Perch could see it (or one of Perch's own hotkeys fired).
    public mutating func keyDown() { if !held.isEmpty { dirty = true } }

    /// The modifiers held changed. True when that was a tap.
    public mutating func flagsChanged(_ now: ShortcutMods, keyDowns: Int, at time: Date = Date()) -> Bool {
        defer { held = now }
        guard !mods.isEmpty else { start = nil; return false }
        if held.isEmpty { start = nil; dirty = false }   // a fresh press
        if now.isEmpty {
            defer { start = nil; dirty = false }
            guard let start, !dirty, keyDowns == startKeyDowns else { return false }
            return time.timeIntervalSince(start) < 0.6
        }
        if !now.isSubset(of: mods) { dirty = true; return false }
        if now == mods, start == nil, !dirty { start = time; startKeyDowns = keyDowns }
        return false
    }

    /// Forget the press under way (the shortcut changed or recording began).
    public mutating func reset() { start = nil; dirty = true }
}
