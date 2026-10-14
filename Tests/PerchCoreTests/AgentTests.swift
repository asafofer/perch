import Testing
@testable import PerchCore

@Suite struct AgentTests {
    @Test func eachAgentResumesWithItsOwnCommand() {
        #expect(Agent.claude.resume("abc") == "claude --resume abc")
        #expect(Agent.codex.resume("abc") == "codex resume abc")
        #expect(Agent.opencode.resume("ses_1") == "opencode -s ses_1")
        #expect(Agent.pi.resume("019f") == "pi --session 019f")
        #expect(Agent.of("pi").short == "pi")
        #expect(Agent.of("unknown") == .claude)
    }

    @Test func processesAreRecognisedByExecutableOrArgv0() {
        #expect(Agent.recognise(executable: "/Users/a/.local/share/claude/versions/2.1.0", argv0: "claude") == .claude)
        #expect(Agent.recognise(executable: "/opt/homebrew/bin/codex", argv0: nil) == .codex)
        #expect(Agent.recognise(executable: "/opt/homebrew/Cellar/opencode/1.18.35/bin/opencode", argv0: "opencode") == .opencode)
        // pi runs under node and renames itself in argv[0].
        #expect(Agent.recognise(executable: "/Users/a/.nvm/versions/node/v22.16.0/bin/node", argv0: "pi") == .pi)
        #expect(Agent.recognise(executable: "/Users/a/.nvm/versions/node/v22.16.0/bin/node", argv0: "node") == nil)
        #expect(Agent.recognise(executable: "/usr/local/bin/node", argv0: "claude") == .claude)
        #expect(Agent.recognise(executable: "/bin/zsh", argv0: "-zsh") == nil)
    }

    @Test func statusWordsUseTheAgentsName() {
        var d = SessionDigest(); d.cwd = "/x/site"; d.lastTimestamp = Date(); d.lastRole = "assistant"; d.lastAssistantText = "Done."
        d.turnOpen = true
        let p = Recap.project(digest: d, git: nil, now: Date(), agent: .opencode, quietFor: 5)!
        #expect(p.app == "opencode")
        #expect(p.status.text == "OpenCode is working")
        #expect(Ask(id: "1", agent: "opencode", tool: "bash", input: ["command": "ls"]).title == "OpenCode wants to run a command")
        #expect(Ask(id: "1", agent: "opencode", tool: "bash", input: ["command": "ls"]).answerable)
        #expect(!Ask(id: "1", agent: "pi", tool: "bash", input: ["command": "ls"]).answerable)
    }
}

import Foundation

@Suite struct PlaceTests {
    @Test func herdrWinsOverTheCmuxTabItsServerStartedIn() {
        let env = ["HERDR_PANE_ID": "w2:p1", "HERDR_SOCKET_PATH": "/Users/a/.config/herdr/herdr.sock", "HERDR_SESSION": "default",
                   "CMUX_SURFACE_ID": "S1", "CMUX_WORKSPACE_ID": "W1", "TERM_PROGRAM": "herdr"]
        #expect(Place.from(environment: env) == .herdr(pane: "w2:p1", socket: "/Users/a/.config/herdr/herdr.sock", session: "default"))
        #expect(Place.from(environment: env).herdrWorkspace == "w2")
        #expect(Place.from(environment: ["CMUX_SURFACE_ID": "S1", "CMUX_WORKSPACE_ID": "W1"]) == .cmux(workspace: "W1", surface: "S1"))
        #expect(Place.from(environment: ["TERM_PROGRAM": "ghostty"]) == .tab)
        #expect(Place.from(environment: ["HERDR_PANE_ID": "w1:p1", "HERDR_SOCKET_PATH": "/s"]) == .herdr(pane: "w1:p1", socket: "/s", session: "default"))
    }

    @Test func aTmuxPaneIsReadFromItsVariables() {
        let tmux = ["TMUX": "/private/tmp/tmux-501/default,4242,0", "TMUX_PANE": "%3"]
        #expect(Place.from(environment: tmux) == .tmux(pane: "%3", socket: "/private/tmp/tmux-501/default"))
        // A tmux server started from a cmux tab passes that tab's variables to its panes; herdr run inside tmux is herdr's.
        #expect(Place.from(environment: tmux.merging(["CMUX_SURFACE_ID": "S1", "CMUX_WORKSPACE_ID": "W1"]) { a, _ in a }) == .tmux(pane: "%3", socket: "/private/tmp/tmux-501/default"))
        #expect(Place.from(environment: tmux.merging(["HERDR_PANE_ID": "w1:p1", "HERDR_SOCKET_PATH": "/s"]) { a, _ in a }) == .herdr(pane: "w1:p1", socket: "/s", session: "default"))
        // A shell that is not in a pane (TMUX without TMUX_PANE) is not in tmux.
        #expect(Place.from(environment: ["TMUX": "/private/tmp/tmux-501/default,4242,0"]) == .tab)
        #expect(TmuxServer.socket("/tmp/a,b/sock,4242,1")?.path == "/tmp/a,b/sock")
        #expect(TmuxServer.socket("/tmp/a,b/sock,4242,1")?.server == 4242)
        #expect(TmuxServer.socket("")?.path == nil)
    }

    @Test func tmuxSaysWhichPaneIsWhereAndWhichClientShowsIt() {
        let out = """
            P\t%0\t/dev/ttys004\tmain
            P\t%3\t/dev/ttys007\twork
            P\t%3\t/dev/ttys007\twork-linked
            P\t%5\t/dev/ttys009\tside
            C\t812\t/dev/ttys002\tmain\t1760430000
            C\t990\t/dev/ttys011\twork\t1760420000
            """
        let s = TmuxServer.parse(out)
        #expect(s.panes["%3"] == TmuxServer.Pane(tty: "/dev/ttys007", sessions: ["work", "work-linked"]))
        #expect(s.clients.count == 2)
        // The client already on the pane's session, though another was used since.
        #expect(s.viewer(of: "%3")?.pid == 990)
        // No client on its session: the one used last, which tmux moves there.
        #expect(s.viewer(of: "%5")?.pid == 812)
        #expect(TmuxServer.parse("P\t%0\t/dev/ttys004\tmain\n").viewer(of: "%0") == nil)
        #expect(TmuxServer.parse("").panes.isEmpty)
    }

    @Test func processArgumentsAndEnvironmentAreRead() {
        var data = Data()
        var argc = Int32(2); data.append(Data(bytes: &argc, count: 4))
        data.append(Data("/usr/local/bin/node\0\0\0\0pi\0--session\0HERDR_PANE_ID=w1:p2\0TERM=xterm\0\0".utf8))
        let a = ProcessArgs.parse(data)
        #expect(a?.executable == "/usr/local/bin/node")
        #expect(a?.argv == ["pi", "--session"])
        #expect(a?.environment == ["HERDR_PANE_ID": "w1:p2", "TERM": "xterm"])
        #expect(ProcessArgs.parse(Data([1, 0])) == nil)
        // node renamed itself to "pi": the rest of its old arguments are zeros, then the environment.
        var renamed = Data(); var two = Int32(2); renamed.append(Data(bytes: &two, count: 4))
        renamed.append(Data("/usr/local/bin/node\0\0pi\0\0\0\0\0\0\0HERDR_PANE_ID=w1:p1\0\0".utf8))
        #expect(ProcessArgs.parse(renamed)?.argv.first == "pi")
        #expect(ProcessArgs.parse(renamed)?.environment["HERDR_PANE_ID"] == "w1:p1")
    }
}

@Suite struct RunningTests {
    func p(_ id: String, _ app: String, _ cwd: String, _ ago: TimeInterval) -> Project {
        var x = Project(id: id, name: id, branch: nil, away: "", at: "", headline: "", context: "", next: "", topic: "", app: app,
                        agents: [AgentStatus(kind: .done, text: "", app: app)], steps: [], sessionId: id, cwd: cwd)
        x.lastActive = Date().addingTimeInterval(-ago); return x
    }

    @Test func aCommandThatNamesItsSessionWinsOverTheNewestInTheFolder() {
        let list = [p("new", "claude", "/a", 10), p("old", "claude", "/a", 600), p("pi1", "pi", "/a", 30)]
        let procs = [Running.Process(agent: "claude", cwd: "/a", argv: ["claude", "--resume", "old"]),
                     Running.Process(agent: "claude", cwd: "/a", argv: ["claude"]),
                     Running.Process(agent: "pi", cwd: "/a", argv: ["pi"])]
        #expect(Running.match(procs, to: list) == [1: 0, 0: 1, 2: 2])
    }

    @Test func herdrsSessionIdNamesTheSession() {
        let list = [p("new", "opencode", "/a", 10), p("old", "opencode", "/a", 600)]
        #expect(Running.match([Running.Process(agent: "opencode", cwd: "/a", argv: ["opencode"], session: "old")], to: list) == [1: 0])
        // Another folder, or another agent, is not the same session.
        #expect(Running.match([Running.Process(agent: "opencode", cwd: "/b", argv: ["opencode"])], to: list).isEmpty)
        #expect(Running.match([Running.Process(agent: "pi", cwd: "/a", argv: ["pi"])], to: list).isEmpty)
    }

    @Test func agentsSideBySideEachKeepTheSessionTheyBegan() {
        let t0 = Date().addingTimeInterval(-900)
        func s(_ id: String, begun: TimeInterval, active: TimeInterval) -> Project {
            var x = p(id, "pi", "/a", 0); x.startedAt = t0.addingTimeInterval(begun); x.lastActive = t0.addingTimeInterval(active); return x
        }
        // herdr's pi started first, cmux's 20 s later; a third pi began a session and has since quit.
        let list = [s("herdr", begun: 3, active: 30), s("cmux", begun: 23, active: 40), s("quit", begun: 330, active: 360)]
        let procs = [Running.Process(agent: "pi", cwd: "/a", argv: ["pi"], started: t0.addingTimeInterval(20)),
                     Running.Process(agent: "pi", cwd: "/a", argv: ["pi"], started: t0)]
        #expect(Running.match(procs, to: list) == [0: 1, 1: 0])
        // Alone, it is the session it used last (after /new).
        #expect(Running.match([Running.Process(agent: "pi", cwd: "/a", argv: ["pi"], started: t0)], to: list) == [2: 0])
    }

    @Test func aFreshAgentIsNotTheFoldersOldSession() {
        let list = [p("old", "pi", "/a", 3600)]
        #expect(Running.match([Running.Process(agent: "pi", cwd: "/a", argv: ["pi"], started: Date().addingTimeInterval(-60))], to: list).isEmpty)
        #expect(Running.match([Running.Process(agent: "pi", cwd: "/a", argv: ["pi"], started: Date().addingTimeInterval(-7200))], to: list) == [0: 0])
    }

    @Test func herdrSeesWhatTheTranscriptCannot() {
        var working = p("s", "pi", "/a", 5); working.agents = [AgentStatus(kind: .running, text: "pi is working", app: "pi")]; working.now = "Running `ls`"
        #expect(HerdrStatus.apply("blocked", to: working).status.text == "pi is waiting for you")
        #expect(HerdrStatus.apply("done", to: working).status.kind == "done")
        #expect(HerdrStatus.apply("done", to: working).now == nil)
        #expect(HerdrStatus.apply("unknown", to: working) == working)
        let finished = p("f", "claude", "/a", 5)
        #expect(HerdrStatus.apply("idle", to: finished) == finished)
        #expect(HerdrStatus.apply("working", to: finished).status.text == "Claude Code is working")
    }
}

@Suite struct ProjectNameTests {
    @Test func aWorktreeIsNamedByItsProjectOrNotAtAll() {
        #expect(Recap.projectName(cwd: "/Users/a/code/perch/.claude/worktrees/wizardly-williams-42a0c0", repo: nil) == "perch")
        #expect(Recap.projectName(cwd: "/Users/a/.codex/worktrees/1a2b/perch", repo: nil) == "perch")
        #expect(Recap.projectName(cwd: "/Users/a/somewhere/worktrees/feature-x", repo: nil) == "")
        #expect(Recap.projectName(cwd: "/Users/a/code/perch-feature", repo: "perch") == "perch")
        #expect(Recap.projectName(cwd: "/Users/a/code/site", repo: nil) == "site")
    }

    @Test func gitNamesTheProjectOfAWorktree() throws {
        // This checkout: a worktree names its project, a main checkout does not need to.
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().path
        let r = SessionScanner.repo(at: here)
        if here.contains("/worktrees/") { #expect(r != nil && r != (here as NSString).lastPathComponent) } else { #expect(r == nil) }
        #expect(SessionScanner.repo(at: "/") == nil)
    }
}

@Suite struct ProjectCopyTests {
    @Test func whatRunsASessionSurvivesEveryRewrite() {
        var p = Project(id: "s", name: "perch", branch: nil, away: "", at: "", headline: "H.", context: "C", next: "", topic: "t", app: "opencode",
                        agents: [AgentStatus(kind: .needsYou, text: "OpenCode is waiting for you", app: "opencode")], steps: [], sessionId: "s", cwd: "/a")
        p.pid = 42; p.host = "herdr"; p.via = "com.cmuxterm.app"; p.terminal = true; p.lastActive = Date(timeIntervalSince1970: 0)
        for q in [p.applying(LiveStatus(kind: .working, at: Date())), p.settled(since: Date())] {
            #expect(q.pid == 42); #expect(q.host == "herdr"); #expect(q.via == "com.cmuxterm.app"); #expect(q.terminal)
        }
        #expect(p.settled(since: Date()).status.kind == "idle")
    }
}
