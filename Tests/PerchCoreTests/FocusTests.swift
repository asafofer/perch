import Testing
@testable import PerchCore

@Suite struct FocusTests {
    private func session(_ id: String, via: String, spot: String?, terminal: Bool = true, app: String = "claude") -> Project {
        var p = Project(id: id, name: id, branch: nil, away: "", at: "", headline: "", context: "", next: "", topic: "", app: app,
                        agents: [], steps: [], sessionId: id, cwd: "/work/\(id)")
        p.terminal = terminal; p.via = via; p.spot = spot
        return p
    }
    private let cmux = "com.cmuxterm.app", ghostty = "com.mitchellh.ghostty"

    @Test func spotsDifferByWhereTheAgentLives() {
        #expect(Spot.key(.cmux(workspace: "w", surface: "S1"), tty: "/dev/ttys001") == "cmux:s1")
        #expect(Spot.key(.tab, tty: "/dev/ttys004") == "tty:/dev/ttys004")
        #expect(Spot.key(.herdr(pane: "w1:p2", socket: "/h.sock", session: "default"), tty: "/dev/ttys004") == Spot.herdr(socket: "/h.sock", pane: "w1:p2"))
    }

    @Test func onlyTheFocusedCmuxSurfaceIsTheSessionYouAreIn() {
        // Several agents in cmux: the first in the list is not the one in front.
        let ps = [session("a", via: cmux, spot: "cmux:s1"), session("b", via: cmux, spot: "cmux:s2"), session("c", via: cmux, spot: "cmux:s3")]
        let r = Focus.inTerminal(ps, app: cmux, looking: Looking(spots: ["cmux:s2"]))
        #expect(r.sure == ["b"]); #expect(r.maybe == ["b"])
    }

    @Test func aSessionThatIsNotRunningIsNeverTheOneYouAreIn() {
        // It remembers cmux as its last place, but no process runs it: a stale row must not stand in for the focused one.
        let ps = [session("old", via: cmux, spot: nil), session("live", via: cmux, spot: "cmux:s2")]
        #expect(Focus.inTerminal(ps, app: cmux, looking: Looking(spots: ["cmux:s2"])).sure == ["live"])
        #expect(Focus.inTerminal(ps, app: cmux, looking: .cannotTell).maybe == ["live"])
    }

    @Test func focusOnAShellWithNoAgentMeansNoSession() {
        let ps = [session("a", via: cmux, spot: "cmux:s1")]
        let r = Focus.inTerminal(ps, app: cmux, looking: Looking(spots: ["cmux:shell"]))
        #expect(r.sure.isEmpty); #expect(r.maybe.isEmpty)
    }

    @Test func whenItCannotTellEveryLiveSessionInThatAppStaysQuiet() {
        let ps = [session("a", via: ghostty, spot: "tty:/dev/ttys001"), session("b", via: ghostty, spot: "tty:/dev/ttys002"), session("c", via: cmux, spot: "cmux:s1")]
        let r = Focus.inTerminal(ps, app: ghostty, looking: .cannotTell)
        #expect(r.sure.isEmpty); #expect(r.maybe == ["a", "b"])
    }

    @Test func aHerdrServerWithSeveralClientsIsMaybeForAllItsPanes() {
        let a = Spot.herdr(socket: "/h.sock", pane: "w1:p1"), b = Spot.herdr(socket: "/h.sock", pane: "w1:p2"), other = Spot.herdr(socket: "/o.sock", pane: "w1:p1")
        let ps = [session("a", via: ghostty, spot: a), session("b", via: ghostty, spot: b), session("o", via: ghostty, spot: other)]
        let r = Focus.inTerminal(ps, app: ghostty, looking: Looking(servers: ["/h.sock"]))
        #expect(r.sure.isEmpty); #expect(r.maybe == ["a", "b"])
        // With its focused pane known, only that one.
        #expect(Focus.inTerminal(ps, app: ghostty, looking: Looking(spots: [b])).sure == ["b"])
    }

    @Test func theCodexAppCountsAllItsThreadsAsMaybe() {
        let ps = [session("t1", via: "", spot: nil, terminal: false, app: "codex"), session("t2", via: "", spot: nil, terminal: false, app: "codex"),
                  session("cli", via: cmux, spot: "cmux:s1", app: "codex")]
        #expect(Focus.inCodexApp(ps) == ["t1", "t2"])
    }
}
