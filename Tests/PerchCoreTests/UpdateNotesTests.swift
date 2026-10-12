import Foundation
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

    @Test func bundledNotesAreReadFromTheFolder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("notes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "Faster lists\n\n- One\n- Two\n".write(to: dir.appendingPathComponent("1.2.3.md"), atomically: true, encoding: .utf8)
        try "\n\n".write(to: dir.appendingPathComponent("1.2.4.md"), atomically: true, encoding: .utf8)
        #expect(UpdateNotes.bundled(version: "1.2.3", in: dir) == UpdateNotes(headline: "Faster lists", bullets: ["One", "Two"]))
        #expect(UpdateNotes.bundled(version: "1.2.4", in: dir) == nil)   // says nothing
        #expect(UpdateNotes.bundled(version: "9.9.9", in: dir) == nil)   // no file
    }
}
