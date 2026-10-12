import XCTest
@testable import PerchCore

final class WarpWindowsTests: XCTestCase {
    let home = "/Users/asaf"

    func testWholePathBeatsFolderName() {
        let titles = ["perch - claude", "~/Documents/perch", "notes"]
        XCTAssertEqual(WarpWindows.match(titles: titles, cwd: "/Users/asaf/Documents/perch", home: home), 1)
    }

    func testFolderNameInATitle() {
        XCTAssertEqual(WarpWindows.match(titles: ["Slack", "✳ token: fix login", "perch"], cwd: "/Users/asaf/code/token", home: home), 1)
    }

    func testLongerNameDoesNotMatch() {
        XCTAssertNil(WarpWindows.match(titles: ["~/Documents/perch-releases", "perches"], cwd: "/Users/asaf/Documents/perch", home: home))
    }

    func testNothingNamesTheFolder() {
        XCTAssertNil(WarpWindows.match(titles: ["zsh", "vim"], cwd: "/Users/asaf/code/token", home: home))
        XCTAssertNil(WarpWindows.match(titles: [], cwd: "/Users/asaf/code/token", home: home))
    }

    func testTiesGoToTheFirst() {
        XCTAssertEqual(WarpWindows.match(titles: ["a perch", "b perch"], cwd: "/Users/asaf/perch", home: home), 0)
    }
}
