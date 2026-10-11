import Testing
@testable import PerchCore

@Suite struct UpdateNotesTests {
    @Test func markdownHeadlineAndBullets() {
        let n = UpdateNotes.parse("Record your own shortcut to open Perch\n\n- Shortcuts work on non-Latin layouts\n- A notch that fits every display\n")
        #expect(n.headline == "Record your own shortcut to open Perch")
        #expect(n.bullets == ["Shortcuts work on non-Latin layouts", "A notch that fits every display"])
    }
    @Test func aHeadingMarkIsDropped() {
        #expect(UpdateNotes.parse("## What's new\n- One thing").headline == "What's new")
    }
    @Test func onlyBulletsTheFirstIsTheHeadline() {
        let n = UpdateNotes.parse("- First\n- Second")
        #expect(n.headline == "First")
        #expect(n.bullets == ["First", "Second"])
    }
    @Test func htmlNotes() {
        let n = UpdateNotes.parse("<h2>Faster</h2><ul><li>One &amp; two</li><li><b>Three</b></li></ul>")
        #expect(n.headline == "Faster")
        #expect(n.bullets == ["One & two", "Three"])
    }
    @Test func aLongListKeepsEveryLine() {
        let list = (1...30).map { "- Line \($0)" }.joined(separator: "\n")
        #expect(UpdateNotes.parse("Head\n" + list).bullets.count == 30)
    }
    @Test func nothingGivesNothing() {
        #expect(UpdateNotes.parse(nil) == UpdateNotes(headline: "", bullets: []))
        #expect(UpdateNotes.parse("") == UpdateNotes(headline: "", bullets: []))
    }
}
