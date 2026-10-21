import Foundation

/// Warp has no AppleScript and no command line. Each session it starts carries a link to its own tab in WARP_FOCUS_URL
/// (`warp://session/<id>`), which brings that tab forward exactly. A session without one (an older Warp) is found by switching
/// tabs with their own keys, one after another, and reading each one through Accessibility: the window's title (the active
/// tab's folder, or the command running in it, `claude`) and the terminal text on screen. This picks the tab that shows a session.
public enum WarpTabs {
    /// The link to a session's own tab, from its environment. Nil when it has none, or it is not a Warp session link.
    public static func focusLink(_ environment: [String: String]) -> URL? {
        guard let s = environment["WARP_FOCUS_URL"], let url = URL(string: s), url.scheme == "warp", url.host == "session",
              url.path.count > 1 else { return nil }
        return url
    }

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
