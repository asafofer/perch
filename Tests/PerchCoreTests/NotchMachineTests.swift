import Foundation
import Testing
@testable import PerchCore

@Suite struct NotchMachineTests {
    @Test func aRowInTheListShowsItsCardWithoutOpeningIt() {
        var m = NotchMachine(projectCount: 3)
        m.send(.openSwitcher); m.send(.show(2))
        #expect(m.phase == .open); #expect(m.selected == 2)
        m.send(.openSwitcher); m.send(.show(7))
        #expect(m.phase == .switcher)   // out of range: stays on the list
    }
    private func machine(_ n: Int = 3) -> NotchMachine { NotchMachine(projectCount: n) }

    @Test func settingsGoesBackWhereItCameFrom() {
        var m = machine(); m.send(.openSwitcher); m.send(.next); m.send(.openSettings)
        #expect(m.settingsFrom == .switcher)
        m.send(.back); #expect(m.phase == .switcher); #expect(m.selected == 1)
        m.send(.show(2)); m.send(.openSettings); m.send(.back)
        #expect(m.phase == .open); #expect(m.selected == 2)
        // from the menu bar or a shortcut there is nothing to go back to: it closes
        var n = machine(); n.send(.openSettings); n.send(.back)
        #expect(n.phase == .idle); #expect(n.settingsFrom == nil)
    }

    @Test func comeBackOpensCard() {
        var m = machine(); m.send(.comeBack)
        #expect(m.phase == .open); #expect(m.selected == 0)
    }
    @Test func comeBackWithNoProjectsStaysClosed() {
        var m = machine(0); m.send(.comeBack)
        #expect(m.phase == .idle)
    }
    @Test func askingForTheListWithNoProjectsShowsItEmpty() {
        var m = machine(0); m.send(.openSwitcher)
        #expect(m.phase == .switcher)
        m.send(.next); m.send(.previous); #expect(m.selected == 0)
        m.send(.back); #expect(m.phase == .switcher)
        m.send(.projectsChanged(count: 0, selected: 0)); #expect(m.phase == .switcher)
        m.send(.projectsChanged(count: 2, selected: 0)); m.send(.next); #expect(m.selected == 1)
    }
    @Test func nextCyclesAndWraps() {
        var m = machine(); m.send(.comeBack)
        m.send(.next); m.send(.next); #expect(m.selected == 2)
        m.send(.next); #expect(m.selected == 0)
        m.send(.previous); #expect(m.selected == 2)
    }
    @Test func confirmRestoresThenCloses() {
        var m = machine(); m.send(.comeBack); m.send(.confirm)
        #expect(m.phase == .restoring)
        m.send(.restoreFinished); #expect(m.phase == .idle)
    }
    @Test func dismissClosesFromEveryOpenPhase() {
        for start: NotchEvent in [.comeBack, .openSwitcher] {
            var m = machine(); m.send(start); m.send(.dismiss)
            #expect(m.phase == .idle)
        }
        var r = machine(); r.send(.comeBack); r.send(.confirm); r.send(.dismiss)
        #expect(r.phase == .idle)
    }
    @Test func timeoutClosesOpenCardUnlessHovering() {
        var m = machine(); m.send(.comeBack); m.send(.hoverChanged(true))
        #expect(!m.autoCollapses)
        m.send(.timeout); #expect(m.phase == .open)
        m.send(.hoverChanged(false)); #expect(m.autoCollapses)
        m.send(.timeout); #expect(m.phase == .idle)
    }
    @Test func timeoutDoesNothingInSwitcher() {
        var m = machine(); m.send(.openSwitcher); m.send(.timeout)
        #expect(m.phase == .switcher)
    }
    @Test func switcherToggleAndSelection() {
        var m = machine(); m.send(.openSwitcher); m.send(.next)
        #expect(m.selected == 1)
        m.send(.confirm); #expect(m.phase == .restoring)
        var t = machine(); t.send(.openSwitcher); t.send(.openSwitcher)
        #expect(t.phase == .idle)
    }
    @Test func openCardCanMoveToSwitcher() {
        var m = machine(); m.send(.comeBack); m.send(.openSwitcher)
        #expect(m.phase == .switcher)
    }
    @Test func closingResetsHover() {
        var m = machine(); m.send(.comeBack); m.send(.hoverChanged(true)); m.send(.dismiss)
        #expect(!m.hovering)
    }
    @Test func eventsAreIgnoredWhenIdle() {
        var m = machine()
        for e: NotchEvent in [.next, .previous, .confirm, .dismiss, .timeout, .restoreFinished] { m.send(e) }
        #expect(m.phase == .idle)
    }
}

@Suite struct NotchMachineChooseTests {
    @Test func chooseSelectsAndRestores() {
        var m = NotchMachine(projectCount: 3); m.send(.openSwitcher); m.send(.choose(2))
        #expect(m.phase == .restoring); #expect(m.selected == 2)
    }
    @Test func chooseOutOfRangeIsIgnored() {
        var m = NotchMachine(projectCount: 3); m.send(.openSwitcher); m.send(.choose(7))
        #expect(m.phase == .switcher)
    }
    @Test func chooseIsIgnoredWhenIdle() {
        var m = NotchMachine(projectCount: 3); m.send(.choose(1))
        #expect(m.phase == .idle)
    }
}

@Suite struct NotchMachineBackTests {
    @Test func backFromListReturnsToTheCardOfTheHighlightedProject() {
        var m = NotchMachine(projectCount: 3); m.send(.comeBack); m.send(.openSwitcher); m.send(.next); m.send(.back)
        #expect(m.phase == .open); #expect(m.selected == 1)
    }
    @Test func backDoesNothingOutsideTheList() {
        var m = NotchMachine(projectCount: 3); m.send(.comeBack); m.send(.back)
        #expect(m.phase == .open)
        var i = NotchMachine(projectCount: 3); i.send(.back); #expect(i.phase == .idle)
    }

    @Test func refreshWhileOpenKeepsTheCardAndClampsSelection() {
        var m = NotchMachine(projectCount: 3)
        m.send(.comeBack); m.send(.next); m.send(.next)
        m.send(.projectsChanged(count: 2, selected: 5))
        #expect(m.phase == .open); #expect(m.projectCount == 2); #expect(m.selected == 1)
        m.send(.projectsChanged(count: 4, selected: 2))
        #expect(m.selected == 2)
    }

    @Test func onboardingOpensFromIdleAndClosesOnDismiss() {
        var m = NotchMachine(projectCount: 0)
        m.send(.openOnboarding); #expect(m.phase == .onboarding)
        m.send(.comeBack); #expect(m.phase == .onboarding)
        m.send(.dismiss); #expect(m.phase == .idle)
    }

    @Test func characterPageOpensFromSettingsAndGoesBack() {
        var m = NotchMachine(projectCount: 2)
        m.send(.openSettings); m.send(.openOnboarding); #expect(m.phase == .onboarding)
        m.send(.openSettings); #expect(m.phase == .settings)
    }

    @Test func settingsOpenFromAnywhereAndCloseOnDismiss() {
        var m = NotchMachine(projectCount: 2)
        m.send(.comeBack); m.send(.openSettings); #expect(m.phase == .settings)
        m.send(.dismiss); #expect(m.phase == .idle)
        m.send(.openSettings); #expect(m.phase == .settings)
    }
}

@Suite struct PutAwayTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func theCardComesBackForFiveMinutesWhileItsSessionIsListed() {
        let away = PutAway(phase: .open, session: "b", replying: true, at: t0)!
        #expect(away.replying)
        #expect(away.recall(ids: ["a", "b", "c"], now: t0.addingTimeInterval(60)) == .reopen(.open, selected: 1))
        // the list reordered while it was closed: it follows the session, not the row
        #expect(away.recall(ids: ["b", "a"], now: t0.addingTimeInterval(299)) == .reopen(.open, selected: 0))
        #expect(away.recall(ids: ["a", "b"], now: t0.addingTimeInterval(PutAway.keeps)) == nil)
        #expect(away.recall(ids: ["a", "c"], now: t0.addingTimeInterval(10)) == nil)   // archived, or off the list
    }
    @Test func theListComesBackWithItsFilterOnTheSameRow() {
        let away = PutAway(phase: .switcher, session: "c", query: "web", at: t0)!
        #expect(away.query == "web"); #expect(!away.replying)
        #expect(away.recall(ids: ["a", "b", "c"], now: t0.addingTimeInterval(5)) == .reopen(.switcher, selected: 2))
        // its row has gone: the list still comes back, on its top row
        #expect(away.recall(ids: ["a"], now: t0.addingTimeInterval(5)) == .reopen(.switcher, selected: nil))
        #expect(away.recall(ids: ["a", "c"], now: t0.addingTimeInterval(PutAway.keeps + 1)) == nil)
    }
    @Test func onlyTheCardAndTheListAreRemembered() {
        #expect(PutAway(phase: .settings, session: "a", at: t0) == nil)
        #expect(PutAway(phase: .onboarding, session: nil, at: t0) == nil)
        #expect(PutAway(phase: .open, session: nil, at: t0) == nil)   // a card without its session is nothing to bring back
        #expect(PutAway(phase: .switcher, session: nil, at: t0) != nil)   // an empty list is
        // a reply belongs to a card, a filter to the list
        #expect(PutAway(phase: .switcher, session: "a", replying: true, at: t0)?.replying == false)
        #expect(PutAway(phase: .open, session: "a", query: "web", at: t0)?.query == "")
    }
    @Test func aClockThatWentBackDoesNotKeepItForever() {
        let away = PutAway(phase: .open, session: "a", at: t0)!
        #expect(away.recall(ids: ["a"], now: t0.addingTimeInterval(-3600)) == nil)
    }
}

@Suite struct NotchMachineReopenTests {
    @Test func reopenGoesStraightBackToTheCard() {
        var m = NotchMachine(projectCount: 3); m.send(.reopen(.open, selected: 2))
        #expect(m.phase == .open); #expect(m.selected == 2)
    }
    @Test func reopenGoesBackToTheListOnItsRow() {
        var m = NotchMachine(projectCount: 3); m.send(.reopen(.switcher, selected: 1))
        #expect(m.phase == .switcher); #expect(m.selected == 1)
        var top = NotchMachine(projectCount: 3); top.send(.reopen(.switcher, selected: nil))
        #expect(top.phase == .switcher); #expect(top.selected == 0)
        var empty = NotchMachine(projectCount: 0); empty.send(.reopen(.switcher, selected: 4))
        #expect(empty.phase == .switcher); #expect(empty.selected == 0)
    }
    @Test func reopenIgnoresWhatItCannotShow() {
        var gone = NotchMachine(projectCount: 2); gone.send(.reopen(.open, selected: 5))
        #expect(gone.phase == .idle)
        var none = NotchMachine(projectCount: 2); none.send(.reopen(.open, selected: nil))
        #expect(none.phase == .idle)
        var set = NotchMachine(projectCount: 2); set.send(.reopen(.settings, selected: 0))
        #expect(set.phase == .idle)
    }
    @Test func reopenOnlyFromClosed() {
        var m = NotchMachine(projectCount: 3); m.send(.openSwitcher); m.send(.reopen(.open, selected: 2))
        #expect(m.phase == .switcher); #expect(m.selected == 0)
        var o = NotchMachine(projectCount: 3); o.send(.openSettings); o.send(.reopen(.open, selected: 1))
        #expect(o.phase == .settings)
    }
    @Test func putAwayThenReopenIsTheSameCard() {
        var m = NotchMachine(projectCount: 3); m.send(.comeBack); m.send(.next); m.send(.dismiss)
        let away = PutAway(phase: .open, session: "b", at: Date())!
        m.send(away.recall(ids: ["a", "b", "c"], now: Date())!)
        #expect(m.phase == .open); #expect(m.selected == 1)
    }
}
