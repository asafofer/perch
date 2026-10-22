import XCTest
@testable import PerchCore

final class WarpTabsTests: XCTestCase {
    let home = "/Users/you"
    func tab(_ title: String, _ text: String = "") -> WarpTabs.Reading { .init(title: title, text: text) }
    func best(_ tabs: [WarpTabs.Reading], cwd: String = "/Users/you/Documents/perch", hints: [String] = []) -> Int? {
        WarpTabs.best(tabs, cwd: cwd, home: home, hints: hints)
    }

    func testASessionsOwnLinkFocusesItsTab() {
        let url = WarpTabs.focusLink(["WARP_FOCUS_URL": "warp://session/fd8db87f850b4f9bbadec5f488208d4c", "TERM_PROGRAM": "WarpTerminal"])
        XCTAssertEqual(url?.absoluteString, "warp://session/fd8db87f850b4f9bbadec5f488208d4c")
    }

    func testOnlyAWarpSessionLinkCounts() {
        XCTAssertNil(WarpTabs.focusLink([:]))
        XCTAssertNil(WarpTabs.focusLink(["WARP_FOCUS_URL": ""]))
        XCTAssertNil(WarpTabs.focusLink(["WARP_FOCUS_URL": "warp://session/"]))
        XCTAssertNil(WarpTabs.focusLink(["WARP_FOCUS_URL": "warp://action/new_tab?path=/tmp"]))
        XCTAssertNil(WarpTabs.focusLink(["WARP_FOCUS_URL": "https://example.com/session/abc"]))
    }

    func testIdleShellNamesItsFolderInTheTitle() {
        XCTAssertEqual(best([tab("~"), tab("~/Documents/perch"), tab("~/code/token")]), 1)
    }

    func testTheWholePathBeatsTheFolderName() {
        XCTAssertEqual(best([tab("perch - claude"), tab("~/Documents/perch")]), 1)
    }

    func testAnAgentRunningTitlesItsTabWithTheCommandSoTheTextDecides() {
        let tabs = [tab("claude", "Welcome back\n~/code/token"), tab("claude", "Welcome back\n~/Documents/perch")]
        XCTAssertEqual(best(tabs), 1)
    }

    func testWhatOnlyThisSessionSaidBeatsTheFolder() {
        // Two tabs in the same folder: the one showing the session's own words wins, wherever it is.
        let tabs = [tab("claude", "~/Documents/perch\nfixing the sidebar"), tab("claude", "~/Documents/perch\nPick up in Warp lands on the wrong tab")]
        XCTAssertEqual(best(tabs, hints: ["Pick up in Warp lands on the wrong tab"]), 1)
    }

    func testAWrappedLineStillMatches() {
        XCTAssertEqual(best([tab("claude", "nothing"), tab("claude", "Pick up in Warp lands\n   on the wrong tab")], hints: ["Pick up in Warp lands on the wrong tab"]), 1)
    }

    func testLongerNameDoesNotMatch() {
        XCTAssertNil(best([tab("~/Documents/perch-releases"), tab("perches")]))
    }

    func testNothingLinksATab() {
        XCTAssertNil(best([tab("zsh"), tab("vim", "hello")], cwd: "/Users/you/code/token"))
        XCTAssertNil(best([]))
    }

    func testTiesGoToTheFirst() {
        XCTAssertEqual(best([tab("a perch"), tab("b perch")], cwd: "/Users/you/perch"), 0)
    }

    func sure(_ tabs: [WarpTabs.Reading], _ index: Int, hints: [String] = []) -> Bool {
        WarpTabs.sure(tabs, index, cwd: "/Users/you/Documents/perch", home: home, hints: hints)
    }

    func testWordsOnlyThatSessionHasMakeItSure() {
        let tabs = [tab("~/Documents/perch", "a shell"), tab("~/Documents/perch", "Pick up in Warp lands on the wrong tab")]
        XCTAssertTrue(sure(tabs, 1, hints: ["Pick up in Warp lands on the wrong tab"]))
    }

    func testTheOnlyTabInItsFolderIsSure() {
        XCTAssertTrue(sure([tab("~"), tab("~/Documents/perch"), tab("~/code/token")], 1))
        // Command+3 to 9 past the last tab change nothing, so the last tab is read again.
        XCTAssertTrue(sure([tab("~"), tab("~/Documents/perch"), tab("~/Documents/perch"), tab("~/Documents/perch")], 1))
    }

    func testTwoTabsInTheSameFolderAreAGuess() {
        XCTAssertFalse(sure([tab("~/Documents/perch", "a shell"), tab("~/Documents/perch", "claude")], 0))
        XCTAssertFalse(sure([tab("~/Documents/perch"), tab("perch - claude")], 0))
        // Two tabs that read the same, followed by another: two tabs, not one read twice.
        XCTAssertFalse(sure([tab("~/Documents/perch"), tab("~/Documents/perch"), tab("~"), tab("~")], 0))
    }
}
