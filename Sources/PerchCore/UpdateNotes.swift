import Foundation

/// What a release says about itself, for the notch: a headline and a few lines behind it.
/// The notes are a small markdown (or HTML) file next to each release: the first plain line is the headline, `- ` lines are the bullets.
public struct UpdateNotes: Equatable, Sendable {
    public var headline: String
    public var bullets: [String]

    public init(headline: String, bullets: [String]) { self.headline = headline; self.bullets = bullets }

    public static func parse(_ text: String?) -> UpdateNotes {
        guard var text, !text.isEmpty else { return UpdateNotes(headline: "", bullets: []) }
        // HTML notes: lists and paragraphs become lines, the rest of the tags go.
        if text.contains("<") {
            text = text.replacingOccurrences(of: "<li[^>]*>", with: "\n- ", options: .regularExpression)
                .replacingOccurrences(of: "</?(p|br|ul|ol|h[1-6]|div)[^>]*>", with: "\n", options: .regularExpression)
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        }
        var headline = "", bullets: [String] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if let first = line.first, "-*•".contains(first), line.dropFirst().first == " " {
                line = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !line.isEmpty { bullets.append(clean(line)) }
            } else if headline.isEmpty {
                headline = clean(String(line.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces))
            }
        }
        // Only bullets: the first one is the headline too.
        if headline.isEmpty, let first = bullets.first { headline = first }
        return UpdateNotes(headline: headline, bullets: Array(bullets.prefix(4)))
    }

    private static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: "[*_`]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&quot;", with: "\"")
    }
}
