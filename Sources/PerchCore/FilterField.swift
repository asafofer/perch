import Foundation

/// What you typed in the list, with a caret and a selection, so Left and Right move through it and Command+A selects it all.
public struct FilterField: Equatable {
    public private(set) var chars: [Character] = []
    public private(set) var caret = 0
    /// The other end of the selection; equal to the caret when nothing is selected.
    public private(set) var anchor = 0

    public init() {}

    public var text: String {
        get { String(chars) }
        set { chars = Array(newValue); caret = chars.count; anchor = caret }
    }
    public var isEmpty: Bool { chars.isEmpty }
    public var range: Range<Int> { min(caret, anchor)..<max(caret, anchor) }
    public var hasSelection: Bool { caret != anchor }
    public var selected: String { String(chars[range]) }

    /// The text is cut into characters again afterwards: a combining accent typed after a letter joins it.
    public mutating func insert(_ s: String) {
        let r = range, head = String(chars[..<r.lowerBound]) + s
        chars = Array(head + String(chars[r.upperBound...]))
        caret = min(head.count, chars.count); anchor = caret
    }
    /// Backspace: the selection, else the character before the caret. Option takes the word before it.
    public mutating func deleteBackward(word: Bool = false) {
        if !hasSelection { guard caret > 0 else { return }; anchor = word ? wordStart(caret) : caret - 1; swap(&caret, &anchor) }
        insert("")
    }
    public mutating func deleteForward() {
        if !hasSelection { guard caret < chars.count else { return }; anchor = caret + 1 }
        insert("")
    }
    public mutating func selectAll() { anchor = 0; caret = chars.count }

    public enum Step { case char, word, edge }
    /// Left (-1) or Right (+1). Shift grows the selection; without it a selection collapses to the end you are heading for (by a character or a word; to an edge it goes on to the edge).
    public mutating func move(_ d: Int, by step: Step = .char, extend: Bool = false) {
        var to: Int
        if hasSelection && !extend && step != .edge { to = d < 0 ? range.lowerBound : range.upperBound }
        else {
            switch step {
            case .edge: to = d < 0 ? 0 : chars.count
            case .word: to = d < 0 ? wordStart(caret) : wordEnd(caret)
            case .char: to = min(max(caret + d, 0), chars.count)
            }
        }
        caret = to
        if !extend { anchor = to }
    }
    /// Right at the end of the text has nowhere to go: Perch uses that to open the row.
    public var atEnd: Bool { caret == chars.count && !hasSelection }

    private func wordStart(_ i: Int) -> Int {
        var j = i
        while j > 0, chars[j - 1].isWhitespace { j -= 1 }
        while j > 0, !chars[j - 1].isWhitespace { j -= 1 }
        return j
    }
    private func wordEnd(_ i: Int) -> Int {
        var j = i
        while j < chars.count, chars[j].isWhitespace { j += 1 }
        while j < chars.count, !chars[j].isWhitespace { j += 1 }
        return j
    }
}
