import Foundation

/// Warp has no AppleScript, no command line and no link that focuses a window or tab it already has, so Perch can only
/// tell its windows apart by their titles (a window is titled after its active tab: the folder, or what runs there).
public enum WarpWindows {
    /// The window that probably holds a session running in `cwd`, as an index into `titles`; nil when none names the folder.
    /// A title with the whole path (or `~/...`) beats one that only has the folder's name; ties go to the first.
    public static func match(titles: [String], cwd: String, home: String) -> Int? {
        let full = cwd.lowercased()
        let tilde = full.hasPrefix(home.lowercased() + "/") ? "~" + full.dropFirst(home.count) : full
        let name = (cwd as NSString).lastPathComponent.lowercased()
        var best: (index: Int, score: Int)?
        for (i, raw) in titles.enumerated() {
            let title = raw.lowercased()
            var score = 0
            if !full.isEmpty, hasWhole(title, full) || hasWhole(title, tilde) { score = 2 }
            else if name.count >= 2, hasWord(title, name) { score = 1 }
            if score > (best?.score ?? 0) { best = (i, score) }
        }
        return best?.index
    }

    /// `path` in `title`, not as the start of a longer path (`~/app` must not match `~/apple`).
    private static func hasWhole(_ title: String, _ path: String) -> Bool {
        var from = title.startIndex
        while let r = title.range(of: path, range: from..<title.endIndex) {
            if r.upperBound == title.endIndex || !isNameCharacter(title[r.upperBound]) { return true }
            from = r.upperBound
        }
        return false
    }

    /// `word` in `title` between characters that cannot be part of a folder name.
    private static func hasWord(_ title: String, _ word: String) -> Bool {
        var from = title.startIndex
        while let r = title.range(of: word, range: from..<title.endIndex) {
            let before = r.lowerBound == title.startIndex || !isNameCharacter(title[title.index(before: r.lowerBound)])
            let after = r.upperBound == title.endIndex || !isNameCharacter(title[r.upperBound])
            if before && after { return true }
            from = r.upperBound
        }
        return false
    }

    private static func isNameCharacter(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" || c == "-" || c == "." }
}
