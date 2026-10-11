import Testing
@testable import PerchCore

@Suite struct KeyLayoutTests {
    @Test func latinLayoutsKeepWhatTheKeyTypes() {
        #expect(KeyLayout.shortcut(typed: "R", keyCode: 15) == "r")
        #expect(KeyLayout.shortcut(typed: ",", keyCode: 43) == ",")
        // Dvorak: the key in the US comma place types "w".
        #expect(KeyLayout.shortcut(typed: "w", keyCode: 43) == "w")
    }

    @Test func hebrewKeysFallBackToTheirUSPlace() {
        #expect(KeyLayout.shortcut(typed: "\u{05EA}", keyCode: 43) == ",")   // comma key types tav
        #expect(KeyLayout.shortcut(typed: "\u{05E8}", keyCode: 15) == "r")
        #expect(KeyLayout.shortcut(typed: "\u{05D0}", keyCode: 8) == "c")
        #expect(KeyLayout.shortcut(typed: "\u{05D0}", keyCode: 9) == "v")
    }

    @Test func anyNonLatinLayoutFallsBackTheSameWay() {
        #expect(KeyLayout.shortcut(typed: "\u{0628}", keyCode: 43) == ",")   // Arabic
        #expect(KeyLayout.shortcut(typed: "\u{0431}", keyCode: 43) == ",")   // Russian
        #expect(KeyLayout.shortcut(typed: "\u{043A}", keyCode: 15) == "r")
        #expect(KeyLayout.shortcut(typed: "\u{03C1}", keyCode: 15) == "r")   // Greek
        #expect(KeyLayout.shortcut(typed: "\u{314A}", keyCode: 8) == "c")    // Korean
    }

    @Test func unknownKeysStayAsTyped() {
        #expect(KeyLayout.shortcut(typed: "\u{05D0}", keyCode: 200) == "\u{05D0}")
        #expect(KeyLayout.shortcut(typed: nil, keyCode: 200) == "")
    }
}
