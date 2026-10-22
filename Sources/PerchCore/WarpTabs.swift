import Foundation

/// Warp has no AppleScript, no command line and no link that focuses a tab it already has. What Perch can do is switch
/// tabs with their own keys, one after another, and read each one through Accessibility: the window's title (the active
/// tab's folder, or the command running in it, `claude`) and the terminal text on screen. This picks the tab that shows a session.
public enum WarpTabs {
    /// What one tab showed when it was in front.
    public struct Reading: Equatable, Sendable {
        public let title: String, text: String
        public init(title: String, text: String) { self.title = title; self.text = text }
    }

    /// A score that means "this tab shows the session itself" (something only that session said), so nothing later can beat it.
    public static let certain = 4

    /// How well a tab fits a session running in `cwd`. `hints` are words that only this session has on screen: its title,
    /// the last thing you asked or the agent said. Zero means nothing links them.
    public static func score(_ r: Reading, cwd: String, home: String, hints: [String]) -> Int {
        let title = squash(r.title), text = squash(r.text)
        var score = 0
        if hints.contains(where: { let h = squash($0); return h.count >= 8 && (text.contains(h) || title.contains(h)) }) { score += certain }
        let full = cwd.lowercased()
        let tilde = full.hasPrefix(home.lowercased() + "/") ? "~" + full.dropFirst(home.count) : full
        if !full.isEmpty {
            if hasWhole(title, full) || hasWhole(title, tilde) { score += 2 }
            else if hasWhole(text, full) || hasWhole(text, tilde) { score += 1 }
        }
        if score == 0 {
            let name = (cwd as NSString).lastPathComponent.lowercased()
            if name.count >= 2, hasWord(title, name) { score = 1 }
        }
        return score
    }

    /// The best tab, as an index into `readings`; nil when none scores. Ties go to the first.
    public static func best(_ readings: [Reading], cwd: String, home: String, hints: [String]) -> Int? {
        var best: (index: Int, score: Int)?
        for (i, r) in readings.enumerated() {
            let s = score(r, cwd: cwd, home: home, hints: hints)
            if s > (best?.score ?? 0) { best = (i, s) }
        }
        return best?.index
    }

    /// Whether the tab at `index` is the session's own, not only the best guess: it shows something only that session said,
    /// or it is the only tab that fits at all. Two tabs in one folder are a guess, and a reply is never pasted into a guess.
    /// The keys past the last tab leave it in front, so the readings that end the list all alike are that one tab. Alike
    /// readings anywhere else are tabs of their own, which cannot be told apart.
    public static func sure(_ readings: [Reading], _ index: Int, cwd: String, home: String, hints: [String]) -> Bool {
        guard readings.indices.contains(index) else { return false }
        if score(readings[index], cwd: cwd, home: home, hints: hints) >= certain { return true }
        var tabs = readings
        while tabs.count > 1, tabs[tabs.count - 1] == tabs[tabs.count - 2] { tabs.removeLast() }
        return tabs.filter { score($0, cwd: cwd, home: home, hints: hints) > 0 }.count == 1
    }

    /// Lowercase, with every run of white space (a wrapped line, a gap) as one space.
    static func squash(_ s: String) -> String { s.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ") }

    /// `path` in `text`, not as the start of a longer path (`~/app` must not match `~/apple`).
    private static func hasWhole(_ text: String, _ path: String) -> Bool {
        var from = text.startIndex
        while let r = text.range(of: path, range: from..<text.endIndex) {
            if r.upperBound == text.endIndex || !isNameCharacter(text[r.upperBound]) { return true }
            from = r.upperBound
        }
        return false
    }

    /// `word` in `text` between characters that cannot be part of a folder name.
    private static func hasWord(_ text: String, _ word: String) -> Bool {
        var from = text.startIndex
        while let r = text.range(of: word, range: from..<text.endIndex) {
            let before = r.lowerBound == text.startIndex || !isNameCharacter(text[text.index(before: r.lowerBound)])
            let after = r.upperBound == text.endIndex || !isNameCharacter(text[r.upperBound])
            if before && after { return true }
            from = r.upperBound
        }
        return false
    }

    private static func isNameCharacter(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" || c == "-" || c == "." }
}
