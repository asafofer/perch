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
