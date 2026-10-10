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
