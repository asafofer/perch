import XCTest
@testable import PerchCore

final class WarpTabsTests: XCTestCase {
    let home = "/Users/asaf"
    func tab(_ title: String, _ text: String = "") -> WarpTabs.Reading { .init(title: title, text: text) }
    func best(_ tabs: [WarpTabs.Reading], cwd: String = "/Users/asaf/Documents/perch", hints: [String] = []) -> Int? {
        WarpTabs.best(tabs, cwd: cwd, home: home, hints: hints)
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
        XCTAssertNil(best([tab("zsh"), tab("vim", "hello")], cwd: "/Users/asaf/code/token"))
        XCTAssertNil(best([]))
    }

    func testTiesGoToTheFirst() {
        XCTAssertEqual(best([tab("a perch"), tab("b perch")], cwd: "/Users/asaf/perch"), 0)
    }
}
