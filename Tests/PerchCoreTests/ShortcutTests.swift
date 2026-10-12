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
        let list = Shortcut.combo(Shortcut.ownMods, keyCode: 37, name: "L")   // Control+Option+L on the Mac, Super+Alt+L on Linux
        #expect(Shortcut.problem(list) == "\(list.label) is the project list")
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
        #expect(r.flagsChanged(mods: []) == .chosen(.tap([.option, .shift])))
    }

    @Test func oneModifierAloneIsRefused() {
        var r = ShortcutRecorder()
        _ = r.flagsChanged(mods: [.option])
        #expect(r.flagsChanged(mods: []) == .refused("A tap needs two or more modifier keys", keys: ["\u{2325}"]))
    }

    @Test func aKeyWithModifiersRecordsACombo() {
        var r = ShortcutRecorder()
        _ = r.flagsChanged(mods: [.control])
        #expect(r.keyDown(keyCode: 49, typed: " ", mods: [.control]) == .chosen(.combo([.control], keyCode: 49, name: "Space")))
        // Letting go of the modifier afterwards is not also a tap.
        #expect(r.flagsChanged(mods: []) == .none)
    }

    @Test func perchsOwnKeysAreRefused() {
        // The list's key: Control+Option+L on the Mac, Super+Alt+L on Linux (Ctrl+Alt+L locks the screen there).
        #if os(Linux)
        #expect(Shortcut.problem(.combo([.command, .option], keyCode: 37, name: "L")) != nil)
        #expect(Shortcut.problem(.combo([.control, .option], keyCode: 37, name: "L")) == nil)
        #else
        #expect(Shortcut.problem(.combo([.control, .option], keyCode: 37, name: "L")) != nil)
        #endif
    }

    @Test func lettingGoOfAComboOneModifierAtATimeKeepsIt() {
        var r = ShortcutRecorder()
        _ = r.flagsChanged(mods: [.control])
        _ = r.flagsChanged(mods: [.control, .option])
        #expect(r.keyDown(keyCode: 40, typed: "k", mods: [.control, .option]) == .chosen(.combo([.control, .option], keyCode: 40, name: "K")))
        // Option comes up before Control: what is left is not a fresh press of Control, and its release is not a refused tap.
        #expect(r.flagsChanged(mods: [.control]) == .none)
        #expect(r.flagsChanged(mods: []) == .none)
        #expect(r.pending == .combo([.control, .option], keyCode: 40, name: "K"))
    }

    @Test func aBareKeyIsRefusedAndRecordingGoesOn() {
        var r = ShortcutRecorder()
        #expect(r.keyDown(keyCode: 0, typed: "a", mods: []) == .refused("Hold \u{2318}, \u{2325} or \u{2303} too", keys: ["A"]))
        #expect(r.flagsChanged(mods: [.command, .option]) == .none)
        #expect(r.flagsChanged(mods: []) == .chosen(.standard))
    }

    @Test func aChoiceIsOnlySavedByReturnAndPressingAgainReplacesIt() {
        var r = ShortcutRecorder()
        _ = r.flagsChanged(mods: [.command, .option])
        #expect(r.flagsChanged(mods: []) == .chosen(.standard))
        // Another try replaces it; nothing is saved yet.
        #expect(r.keyDown(keyCode: 49, typed: " ", mods: [.control]) == .chosen(.combo([.control], keyCode: 49, name: "Space")))
        _ = r.flagsChanged(mods: [])
        #expect(r.keyDown(keyCode: 36, typed: "\r", mods: []) == .record(.combo([.control], keyCode: 49, name: "Space")))
    }

    @Test func aRefusedTryKeepsTheChoiceAndReturnWithNothingChosenIsRefused() {
        var r = ShortcutRecorder()
        #expect(r.keyDown(keyCode: 36, typed: "\r", mods: []) != .none)
        if case .record = r.keyDown(keyCode: 36, typed: "\r", mods: []) { Issue.record("saved nothing") }
        _ = r.flagsChanged(mods: [.command, .option]); _ = r.flagsChanged(mods: [])
        if case .refused = r.keyDown(keyCode: 12, typed: "q", mods: [.command]) {} else { Issue.record("expected a refusal") }
        #expect(r.keyDown(keyCode: 36, typed: "\r", mods: []) == .record(.standard))
    }

    @Test func escapeCancels() {
        var r = ShortcutRecorder()
        #expect(r.keyDown(keyCode: 53, typed: nil, mods: []) == .cancel)
    }
}

@Suite struct ModifierTapTests {
    let t0 = Date(timeIntervalSince1970: 1000)
    func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }

    @Test func aQuickTapCounts() {
        var t = ModifierTap([.command, .option])
        #expect(t.flagsChanged([.command], keyDowns: 5, at: at(0)) == false)
        #expect(t.flagsChanged([.command, .option], keyDowns: 5, at: at(0.05)) == false)
        #expect(t.flagsChanged([], keyDowns: 5, at: at(0.2)) == true)
    }

    @Test func aSlowTapDoesNot() {
        var t = ModifierTap([.command, .option])
        _ = t.flagsChanged([.command, .option], keyDowns: 0, at: at(0))
        #expect(t.flagsChanged([], keyDowns: 0, at: at(0.7)) == false)
    }

    @Test func anotherAppsShortcutWithAnExtraModifierIsNotATap() {
        // Command+Option+Shift+L for another app, Shift let go before Command and Option.
        var t = ModifierTap([.command, .option])
        _ = t.flagsChanged([.command], keyDowns: 9, at: at(0))
        _ = t.flagsChanged([.command, .option], keyDowns: 9, at: at(0.02))
        _ = t.flagsChanged([.command, .option, .shift], keyDowns: 9, at: at(0.04))
        _ = t.flagsChanged([.command, .option], keyDowns: 10, at: at(0.15))   // L went to the other app
        #expect(t.flagsChanged([], keyDowns: 10, at: at(0.2)) == false)
    }

    @Test func shiftPressedFirstAndLetGoFirstIsNotATap() {
        var t = ModifierTap([.command, .option])
        _ = t.flagsChanged([.shift], keyDowns: 0, at: at(0))
        _ = t.flagsChanged([.shift, .command, .option], keyDowns: 0, at: at(0.05))
        _ = t.flagsChanged([.command, .option], keyDowns: 1, at: at(0.1))
        #expect(t.flagsChanged([], keyDowns: 1, at: at(0.15)) == false)
    }

    @Test func aKeyAnotherAppTookIsNotATap() {
        // Command+Option+L held by another app's hotkey: Perch never sees the L, only the count going up.
        var t = ModifierTap([.command, .option])
        _ = t.flagsChanged([.command, .option], keyDowns: 3, at: at(0))
        #expect(t.flagsChanged([], keyDowns: 4, at: at(0.2)) == false)
    }

    @Test func aKeySeenDuringThePressIsNotATap() {
        var t = ModifierTap([.command, .option])
        _ = t.flagsChanged([.command, .option], keyDowns: 3, at: at(0))
        t.keyDown()
        #expect(t.flagsChanged([], keyDowns: 3, at: at(0.2)) == false)
    }

    @Test func typingBeforeThePressDoesNotSpoilIt() {
        var t = ModifierTap([.command, .option])
        t.keyDown()
        _ = t.flagsChanged([.command, .option], keyDowns: 8, at: at(0))
        #expect(t.flagsChanged([], keyDowns: 8, at: at(0.2)) == true)
    }

    @Test func theNextCleanTapCountsAfterADirtyOne() {
        var t = ModifierTap([.command, .option])
        _ = t.flagsChanged([.command, .option, .shift], keyDowns: 0, at: at(0))
        _ = t.flagsChanged([], keyDowns: 1, at: at(0.1))
        _ = t.flagsChanged([.command, .option], keyDowns: 1, at: at(1))
        #expect(t.flagsChanged([], keyDowns: 1, at: at(1.2)) == true)
    }

    @Test func noModifiersMeansNoTap() {
        var t = ModifierTap([])
        _ = t.flagsChanged([.command, .option], keyDowns: 0, at: at(0))
        #expect(t.flagsChanged([], keyDowns: 0, at: at(0.1)) == false)
    }
}
