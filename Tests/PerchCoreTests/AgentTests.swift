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
