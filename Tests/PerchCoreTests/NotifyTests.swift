import Testing
@testable import PerchCore

@Suite struct NotifyTests {
    @Test func everythingIsOnByDefault() {
        #expect(NotifyKinds.off(from: []).isEmpty)
    }

    @Test func unknownNamesAreDropped() {
        #expect(NotifyKinds.off(from: ["done", "bogus", ""]) == ["done"])
    }

    @Test func switchingOffAndOn() {
        let off = NotifyKinds.toggled([], kind: "done", enabled: false)
        #expect(off == ["done"])
        #expect(NotifyKinds.toggled(off, kind: "run", enabled: false) == ["done", "run"])
        #expect(NotifyKinds.toggled(off, kind: "done", enabled: true).isEmpty)
    }

    @Test func anUnknownKindChangesNothing() {
        #expect(NotifyKinds.toggled(["done"], kind: "bogus", enabled: false) == ["done"])
        #expect(NotifyKinds.toggled(["done"], kind: "bogus", enabled: true) == ["done"])
    }

    @Test func theNamesAreTheOnesThePageUses() {
        #expect(NotifyKind.allCases.map(\.rawValue) == ["done", "run", "ask", "plan", "error"])
    }
}
