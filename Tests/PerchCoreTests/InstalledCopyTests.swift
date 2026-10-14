import Foundation
import Testing
@testable import PerchCore

@Suite struct InstalledCopyTests {
    let running = URL(fileURLWithPath: "/Users/me/perch/.claude/worktrees/x/build/Perch.app")
    func url(_ p: String) -> URL { URL(fileURLWithPath: p) }

    @Test func theCopyInApplications() {
        #expect(InstalledCopy.pick([running, url("/Applications/Perch.app")], running: running) == url("/Applications/Perch.app"))
    }
    @Test func neverTheOneRunning() {
        #expect(InstalledCopy.pick([running], running: running) == nil)
    }
    @Test func otherBuildsAreNotInstalled() {
        let builds = [url("/Users/me/perch/build/Perch.app"), url("/Users/me/perch/.build/debug/Perch.app"),
                      url("/Users/me/Library/Developer/Xcode/DerivedData/Perch/Build/Products/Debug/Perch.app"), url("/Users/me/.Trash/Perch.app")]
        #expect(InstalledCopy.pick(builds, running: running) == nil)
    }
    @Test func applicationsWinsOverDownloads() {
        let found = [url("/Users/me/Downloads/Perch.app"), url("/Applications/Perch.app")]
        #expect(InstalledCopy.pick(found, running: running) == url("/Applications/Perch.app"))
    }
    @Test func theUsersOwnApplicationsCounts() {
        #expect(InstalledCopy.pick([url("/Users/me/Applications/Perch.app")], running: running) == url("/Users/me/Applications/Perch.app"))
    }
    @Test func anUnzippedCopyElsewhereStillCounts() {
        #expect(InstalledCopy.pick([url("/Users/me/Downloads/Perch.app")], running: running) == url("/Users/me/Downloads/Perch.app"))
    }
}
