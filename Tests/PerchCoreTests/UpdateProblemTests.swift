import Foundation
import Testing
@testable import PerchCore

@Suite struct UpdateProblemTests {
    private func sparkle(_ code: Int) -> UpdateProblem.ErrorRef { .init(domain: "SUSparkleErrorDomain", code: code) }
    private func net(_ code: Int) -> UpdateProblem.ErrorRef { .init(domain: NSURLErrorDomain, code: code) }

    @Test func downloadsFolderSaysToMoveIt() {
        for code in [1005, 1003] {
            let p = UpdateProblem.classify([sparkle(code)], updating: false)
            #expect(p.fix == .move)
            #expect(p.short == "move Perch to Applications")
            #expect(p.during == "update")   // it is the update that cannot go: the words say so even when it was a check
        }
    }
    @Test func offlineIsFoundUnderSparkle() {
        // a download that failed because the Mac is offline: Sparkle's error with the network's inside
        let p = UpdateProblem.classify([sparkle(2001), net(-1009)], updating: true)
        #expect(p.short == "no connection")
        #expect(p.during == "update")
        #expect(p.fix == .retry)
    }
    @Test func offlineWhileChecking() {
        #expect(UpdateProblem.classify([sparkle(1002), net(-1001)], updating: false).during == "check")
    }
    @Test func aFeedThatWillNotReadIsACheck() {
        let p = UpdateProblem.classify([sparkle(1000)], updating: true)
        #expect(p.short == "couldn\u{2019}t check")
        #expect(p.during == "check")
    }
    @Test func downloadVerifyAndInstallKindsAreTold() {
        #expect(UpdateProblem.classify([sparkle(2001)], updating: true).short == "couldn\u{2019}t download")
        for code in [3000, 3001, 3002] { #expect(UpdateProblem.classify([sparkle(code)], updating: true).short == "couldn\u{2019}t verify") }
        #expect(UpdateProblem.classify([sparkle(4005)], updating: true).short == "couldn\u{2019}t install")
    }
    @Test func aFolderItCannotWriteToSaysToMove() {
        for code in [4000, 4012] { #expect(UpdateProblem.classify([sparkle(code)], updating: true).fix == .move) }
    }
    @Test func notReopeningHasNothingToPress() {
        #expect(UpdateProblem.classify([sparkle(4004)], updating: true).fix == .none)
    }
    @Test func anythingElseSaysSoPlainly() {
        let p = UpdateProblem.classify([.init(domain: "Other", code: 7)], updating: false)
        #expect(p.short == "couldn\u{2019}t check")
        #expect(p.fix == .retry)
        #expect(UpdateProblem.classify([], updating: true).short == "couldn\u{2019}t update")
    }
    @Test func aMacThatCannotRunTheUpdate() {
        #expect(UpdateProblem.noUpdate(reason: 5)?.short == "needs Apple silicon")
        #expect(UpdateProblem.noUpdate(reason: 3, minimumOS: "26.0")?.line == "This version needs macOS 26.0 or later.")
        #expect(UpdateProblem.noUpdate(reason: 3)?.short == "needs newer macOS")
        #expect(UpdateProblem.noUpdate(reason: 3)?.fix == UpdateProblem.Fix.none)
    }
    @Test func upToDateIsNoProblem() {
        for reason in [0, 1, 2, 4] { #expect(UpdateProblem.noUpdate(reason: reason) == nil) }
    }
}
