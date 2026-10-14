import Foundation
import Testing
@testable import PerchCore

@Suite struct AccessLossTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func neverHadItSaysNothing() {
        var a = AccessLoss(had: false, hadOn: nil, said: false)
        a.observe(trusted: false, build: "200", now: t0)
        #expect(!a.lost)
        #expect(a.row(now: t0) == nil)
        #expect(a.card(carried: false) == nil)
    }
    @Test func havingItIsRemembered() {
        var a = AccessLoss(had: false, hadOn: nil, said: false)
        a.observe(trusted: true, build: "200", now: t0)
        #expect(a.had && a.hadOn == "200")
        #expect(a.row(now: t0) == nil)
    }
    @Test func lostAfterAnUpdateIsSaidOnTheUpdatesCard() {
        // The new build is signed another way: the switch Perch had no longer counts.
        var a = AccessLoss(had: true, hadOn: "200", said: false)
        a.observe(trusted: false, build: "201", now: t0)
        #expect(a.lost)
        #expect(a.afterUpdate(build: "201"))
        #expect(a.card(carried: false) == .lost)
        #expect(a.row(now: t0) == .lost)
        a.markSaid()   // Got it on What's new: the card carried it
        #expect(a.row(now: t0) == nil)
    }
    @Test func turnedOffWhileRunningIsNotAnUpdate() {
        var a = AccessLoss(had: false, hadOn: nil, said: false)
        a.observe(trusted: true, build: "200", now: t0)
        a.observe(trusted: false, build: "200", now: t0)
        #expect(a.lost)
        #expect(!a.afterUpdate(build: "200"))
        #expect(a.row(now: t0) == .lost)
    }
    @Test func saidOncePerLossAcrossLaunches() {
        var a = AccessLoss(had: true, hadOn: "200", said: false)
        a.observe(trusted: false, build: "200", now: t0)
        a.markSaid()
        #expect(a.row(now: t0) == nil)
        // Perch quits and opens again, still without it: the kept values say it was said
        var b = AccessLoss(had: a.had, hadOn: a.hadOn, said: a.said)
        b.observe(trusted: false, build: "200", now: t0)
        #expect(b.row(now: t0) == nil)
        #expect(b.lost)   // Settings still shows its row
    }
    @Test func aNewLossIsSaidAgain() {
        var a = AccessLoss(had: true, hadOn: "200", said: false)
        a.observe(trusted: false, build: "200", now: t0)
        let first = a.losses
        a.markSaid()
        a.observe(trusted: true, build: "200", now: t0)    // allowed again from Settings
        #expect(!a.said)
        a.observe(trusted: false, build: "200", now: t0)   // and turned off once more
        #expect(a.row(now: t0) == .lost)
        #expect(a.losses == first + 1)
    }
    @Test func allowWaitsForTheSwitchThenSaysAllowed() {
        var a = AccessLoss(had: true, hadOn: "200", said: false)
        a.observe(trusted: false, build: "201", now: t0)
        a.allow()
        #expect(a.row(now: t0) == .asked)
        #expect(a.card(carried: true) == .asked)
        a.observe(trusted: false, build: "201", now: t0.addingTimeInterval(2))
        #expect(a.row(now: t0) == .asked)   // still off: it keeps waiting
        let on = a.observe(trusted: true, build: "201", now: t0.addingTimeInterval(5))
        #expect(on)
        #expect(a.row(now: t0.addingTimeInterval(6)) == .granted)
        #expect(a.row(now: t0.addingTimeInterval(5 + AccessLoss.grantedFor + 0.1)) == nil)
        #expect(a.card(carried: true) == .granted)
        #expect(a.card(carried: false) == nil)
        #expect(a.hadOn == "201")
    }
    @Test func laterWhileWaitingPutsItAway() {
        var a = AccessLoss(had: true, hadOn: "200", said: false)
        a.observe(trusted: false, build: "200", now: t0)
        a.allow(); a.markSaid()
        #expect(a.row(now: t0) == nil)
    }
    @Test func grantedWithoutAllowSaysNothingOnTheNotch() {
        // turned on from Settings or System Settings directly: Settings shows it, the notch keeps quiet
        var a = AccessLoss(had: true, hadOn: "200", said: false)
        a.observe(trusted: false, build: "200", now: t0)
        let on = a.observe(trusted: true, build: "200", now: t0)
        #expect(on)
        #expect(a.row(now: t0) == nil)
    }
    @Test func anInstallFromBeforeTheFlagLosesItOnTheUpdate() {
        // set up on an earlier build that never kept `had`, updated to one signed another way
        var a = AccessLoss.seeded(had: nil, hadOn: nil, said: false, onboarded: true)
        a.observe(trusted: false, build: "201", now: t0)
        #expect(a.lost)
        #expect(a.afterUpdate(build: "201"))
        #expect(a.card(carried: false) == .lost)
    }
    @Test func anInstallFromBeforeTheFlagStillTrustedShowsNothing() {
        var a = AccessLoss.seeded(had: nil, hadOn: nil, said: false, onboarded: true)
        let on = a.observe(trusted: true, build: "201", now: t0)
        #expect(!on)
        #expect(!a.lost && a.had && a.hadOn == "201")
        #expect(a.row(now: t0) == nil)
        #expect(a.card(carried: false) == nil)
    }
    @Test func aFreshInstallShowsNothing() {
        var a = AccessLoss.seeded(had: nil, hadOn: nil, said: false, onboarded: false)
        a.observe(trusted: false, build: "201", now: t0)
        #expect(!a.lost)
        #expect(a.row(now: t0) == nil)
        #expect(a.card(carried: false) == nil)
    }
    @Test func keptValuesWinOverSeeding() {
        let a = AccessLoss.seeded(had: false, hadOn: nil, said: false, onboarded: true)
        #expect(!a.had)
        let b = AccessLoss.seeded(had: true, hadOn: "200", said: true, onboarded: true)
        #expect(b.had && b.hadOn == "200" && b.said)
    }
    @Test func allowDoesNothingWhenNotLost() {
        var a = AccessLoss(had: true, hadOn: "200", said: false)
        a.observe(trusted: true, build: "200", now: t0)
        a.allow()
        #expect(!a.asked)
        let again = a.observe(trusted: true, build: "200", now: t0)
        #expect(!again)   // already on: nothing to restart
    }
}
