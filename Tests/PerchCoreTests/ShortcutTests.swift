import Foundation
import Testing
@testable import PerchCore

@Suite struct ShortcutTests {
    @Test func standardIsTheCommandOptionTap() {
        #expect(Shortcut.standard.keys == ["\u{2325}", "\u{2318}"])
        #expect(Shortcut.standard.isStandard)
    }

    @Test func modifiersAreWrittenTheMacWay() {
        #expect(ShortcutMods([.command, .control, .shift, .option]).glyphs == ["\u{2303}", "\u{2325}", "\u{21E7}", "\u{2318}"])
        #expect(Shortcut.combo([.control], keyCode: 49, name: "Space").keys == ["\u{2303}", "Space"])
    }

    @Test func aTapNeedsTwoModifiers() {
        #expect(Shortcut.problem(.tap([.option])) != nil)
        #expect(Shortcut.problem(.tap([.option, .shift])) == nil)
    }

    @Test func aComboNeedsAModifierThatIsNotJustShift() {
        #expect(Shortcut.problem(.combo([], keyCode: 0, name: "A")) != nil)
        #expect(Shortcut.problem(.combo([.shift], keyCode: 0, name: "A")) != nil)
        #expect(Shortcut.problem(.combo([.control], keyCode: 49, name: "Space")) == nil)
        #expect(Shortcut.problem(.combo([.command, .shift], keyCode: 0, name: "A")) == nil)
    }

    @Test func perchsOwnAndEverySystemShortcutIsRefusedWithAReason() {
        #expect(Shortcut.problem(.combo([.control, .option], keyCode: 37, name: "L")) == "\u{2303}\u{2325}L is the project list")
        #expect(Shortcut.problem(.combo([.command], keyCode: 12, name: "Q")) == "\u{2318}Q is Quit in every app")
        #expect(Shortcut.problem(.combo([.command, .option], keyCode: 16, name: "Y")) != nil)
        #expect(Shortcut.problem(.combo([.command, .option], keyCode: 5, name: "G")) == nil)
    }

    @Test func keysAreNamedByCodeOrByWhatTheyType() {
        #expect(Shortcut.name(keyCode: 49, typed: " ") == "Space")
        #expect(Shortcut.name(keyCode: 126, typed: nil) == "\u{2191}")
        #expect(Shortcut.name(keyCode: 5, typed: "g") == "G")
        // Hebrew layout: the key in the US "r" place.
        #expect(Shortcut.name(keyCode: 15, typed: "\u{05E8}") == "R")
    }

    @Test func roundTripsThroughJSON() throws {
        let s = Shortcut.combo([.control, .shift], keyCode: 49, name: "Space")
        let back = try JSONDecoder().decode(Shortcut.self, from: JSONEncoder().encode(s))
        #expect(back == s)
    }

    @Test func releasingModifiersTogetherRecordsATap() {
        var r = ShortcutRecorder()
        #expect(r.flagsChanged(mods: [.option]) == .none)
        #expect(r.flagsChanged(mods: [.option, .shift]) == .none)
        #expect(r.flagsChanged(mods: [.shift]) == .none)
        #expect(r.flagsChanged(mods: []) == .record(.tap([.option, .shift])))
    }

    @Test func oneModifierAloneIsRefused() {
        var r = ShortcutRecorder()
        _ = r.flagsChanged(mods: [.option])
        #expect(r.flagsChanged(mods: []) == .refused("A tap needs two or more modifier keys", keys: ["\u{2325}"]))
    }

    @Test func aKeyWithModifiersRecordsACombo() {
        var r = ShortcutRecorder()
        _ = r.flagsChanged(mods: [.control])
        #expect(r.keyDown(keyCode: 49, typed: " ", mods: [.control]) == .record(.combo([.control], keyCode: 49, name: "Space")))
        // Letting go of the modifier afterwards is not also a tap.
        #expect(r.flagsChanged(mods: []) == .none)
    }

    @Test func aBareKeyIsRefusedAndRecordingGoesOn() {
        var r = ShortcutRecorder()
        #expect(r.keyDown(keyCode: 0, typed: "a", mods: []) == .refused("Hold \u{2318}, \u{2325} or \u{2303} too", keys: ["A"]))
        #expect(r.flagsChanged(mods: [.command, .option]) == .none)
        #expect(r.flagsChanged(mods: []) == .record(.standard))
    }

    @Test func escapeCancels() {
        var r = ShortcutRecorder()
        #expect(r.keyDown(keyCode: 53, typed: nil, mods: []) == .cancel)
    }
}
