import Testing
@testable import PerchCore

@Suite struct FilterFieldTests {
    private func field(_ s: String) -> FilterField { var f = FilterField(); f.insert(s); return f }

    @Test func typingGoesAtTheCaret() {
        var f = field("ac")
        f.move(-1); f.insert("b")
        #expect(f.text == "abc" && f.caret == 2)
    }

    @Test func leftAndRightWalkTheTextAndStopAtTheEnds() {
        var f = field("ab")
        f.move(-1); f.move(-1); f.move(-1)
        #expect(f.caret == 0)
        f.move(1); f.move(1); f.move(1)
        #expect(f.caret == 2 && f.atEnd)
    }

    @Test func selectAllThenTypingReplacesIt() {
        var f = field("hello")
        f.selectAll()
        #expect(f.selected == "hello")
        f.insert("x")
        #expect(f.text == "x" && f.caret == 1 && !f.hasSelection)
    }

    @Test func backspaceDeletesTheSelectionOrTheCharacterBeforeTheCaret() {
        var f = field("abc")
        f.move(-1); f.deleteBackward()
        #expect(f.text == "ac" && f.caret == 1)
        f.selectAll(); f.deleteBackward()
        #expect(f.isEmpty)
    }

    @Test func arrowsCollapseASelectionToTheSideYouHeadFor() {
        var f = field("abc")
        f.selectAll(); f.move(-1)
        #expect(f.caret == 0 && !f.hasSelection)
        f.selectAll(); f.move(1)
        #expect(f.caret == 3 && !f.hasSelection)
    }

    @Test func shiftGrowsTheSelection() {
        var f = field("abc")
        f.move(-1, extend: true); f.move(-1, extend: true)
        #expect(f.selected == "bc")
    }

    @Test func wordsAndEdges() {
        var f = field("one two three")
        f.move(-1, by: .word); #expect(f.caret == 8)
        f.move(-1, by: .word); #expect(f.caret == 4)
        f.move(-1, by: .edge); #expect(f.caret == 0)
        f.move(1, by: .word); #expect(f.caret == 3)
        f.move(1, by: .edge); #expect(f.atEnd)
        f.deleteBackward(word: true); #expect(f.text == "one two ")
    }

    @Test func forwardDelete() {
        var f = field("abc")
        f.move(-1, by: .edge); f.deleteForward()
        #expect(f.text == "bc" && f.caret == 0)
    }

    @Test func settingTheTextPutsTheCaretAtTheEnd() {
        var f = field("abc")
        f.move(-1); f.text = ""
        #expect(f.isEmpty && f.caret == 0)
    }

    @Test func aCombiningAccentJoinsTheLetterBeforeIt() {
        var f = field("e")
        f.insert("\u{0301}")
        #expect(f.chars.count == 1 && f.caret == 1)
        f.deleteBackward()
        #expect(f.isEmpty)
    }

    @Test func aWordMoveCollapsesASelectionFirst() {
        var f = field("one two three")
        f.selectAll(); f.move(-1, by: .word)
        #expect(f.caret == 0 && !f.hasSelection)
        f.selectAll(); f.move(1, by: .word)
        #expect(f.atEnd)
    }
}
