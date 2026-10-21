import Foundation
import Testing
@testable import PerchCore

@Suite struct NewSessionTests {
    private func session(_ id: String, app: String = "claude", terminal: Bool = false, cwd: String?, active: Date? = nil, started: Date? = nil, sessionId: String? = nil) -> Project {
        var p = Project(id: id, name: id, branch: nil, away: "4m", at: "", headline: "", context: "", next: "", topic: "", app: app,
                        agents: [], steps: [], sessionId: sessionId ?? id, cwd: cwd)
        p.terminal = terminal; p.lastActive = active; p.startedAt = started
        return p
    }

    @Test func offersTheAppsAndCommandsOnThisMac() {
        let all = NewSession.choices(claudeApp: true, codexApp: true, commands: ["claude", "codex", "opencode", "pi"]).map(\.id)
        #expect(all == ["claude", "claude-code", "codex", "codex-cli", "opencode", "pi"])
        // no Codex app: its command line tool is just Codex
        let cli = NewSession.choices(claudeApp: false, codexApp: false, commands: ["codex"])
        #expect(cli.map(\.name) == ["Codex"]); #expect(cli[0].terminal)
    }

    @Test func foldersAreNewestFirstOnceEachWorktreesCountAsTheirRepo() {
        let now = Date()
        let list = [session("a", cwd: "/u/perch", active: now.addingTimeInterval(-600)),
                    session("b", cwd: "/u/perch/.claude/worktrees/x", active: now),
                    session("c", cwd: "/u/site", active: now.addingTimeInterval(-60)),
                    session("d", cwd: "/Users/u/Library/Application Support/Claude/scratch-workspaces/abc", active: now),
                    session("e", cwd: nil, active: now)]
        let f = NewSession.folders(list)
        #expect(f.map(\.path) == ["/u/perch", "/u/site"])
        #expect(f[0].name == "perch"); #expect(f[0].away == "4m")
    }

    @Test func startsOnTheSessionYouAreLookingAtElseWhatYouUsedLast() {
        let choices = NewSession.choices(claudeApp: true, codexApp: true, commands: ["claude", "pi"])
        let folders = [NewSession.Folder(name: "site", path: "/u/site", lastActive: nil), NewSession.Folder(name: "perch", path: "/u/perch", lastActive: nil)]
        let looking = session("x", app: "claude", terminal: true, cwd: "/u/perch/.claude/worktrees/w")
        let d = NewSession.defaults(looking: looking, lastChoice: "codex", lastFolder: "/u/site", choices: choices, folders: folders)
        #expect(d.choice == "claude-code"); #expect(d.folder == "/u/perch")
        let none = NewSession.defaults(looking: nil, lastChoice: "pi", lastFolder: "/u/gone", choices: choices, folders: folders)
        #expect(none.choice == "pi"); #expect(none.folder == "/u/site")   // a folder no longer offered: the newest
    }

    @Test func commandsCarryThePromptQuotedAndAnIdWhereTheAgentTakesOne() {
        #expect(NewSession.command(agent: "claude", prompt: "fix it's header", sessionId: "abc") == "claude --session-id abc 'fix it'\\''s header'")
        #expect(NewSession.command(agent: "codex", prompt: "go") == "codex 'go'")
        #expect(NewSession.command(agent: "opencode", prompt: "go") == "opencode --prompt 'go'")
        #expect(NewSession.command(agent: "pi", prompt: "go", sessionId: "s1") == "pi --session-id s1 'go'")
    }

    @Test func theNewSessionIsOneNotSeenBeforeOfThatAgentAndFolderBegunSinceItWasStarted() {
        let t = Date()
        let choice = NewSession.Choice(id: "claude", agent: "claude", terminal: false, name: "Claude")
        let old = session("old", cwd: "/u/perch", started: t.addingTimeInterval(-3600))
        let codex = session("cx", app: "codex", cwd: "/u/perch", started: t)
        let elsewhere = session("el", cwd: "/u/site", started: t)
        let fresh = session("new", cwd: "/u/perch/.claude/worktrees/abc", started: t.addingTimeInterval(2))
        let list = [old, codex, elsewhere, fresh]
        #expect(NewSession.started(in: list, choice: choice, folder: "/u/perch", since: t, known: ["old"])?.id == "new")
        #expect(NewSession.started(in: [old, codex, elsewhere], choice: choice, folder: "/u/perch", since: t, known: ["old"]) == nil)
        // asked to confirm, where another folder can be picked: a new one of that agent counts wherever it runs
        #expect(NewSession.started(in: [old, codex, elsewhere], choice: choice, folder: "/u/perch", since: t, known: ["old"], anyFolder: true)?.id == "el")
        // with an id, only that one
        let pi = session("p", app: "pi", terminal: true, cwd: "/u", started: t, sessionId: "s1")
        let piChoice = NewSession.Choice(id: "pi", agent: "pi", terminal: true, name: "pi")
        #expect(NewSession.started(in: [pi], choice: piChoice, folder: nil, since: t, known: [], sessionId: "s1")?.id == "p")
        #expect(NewSession.started(in: [pi], choice: piChoice, folder: nil, since: t, known: [], sessionId: "s2") == nil)
    }

    @Test func fromTheListItGoesBackThereFromAnywhereItCloses() {
        var m = NotchMachine(projectCount: 3)
        m.send(.openSwitcher); m.send(.openNew)
        #expect(m.phase == .newSession); #expect(m.newFrom == .switcher)
        m.send(.back); #expect(m.phase == .switcher)
        m.send(.openNew); m.send(.started); #expect(m.phase == .switcher)
        var n = NotchMachine(projectCount: 3)
        n.send(.openNew); #expect(n.phase == .newSession); #expect(n.newFrom == nil)
        n.send(.started); #expect(n.phase == .idle)
        n.send(.openNew); n.send(.back); #expect(n.phase == .idle)
        n.send(.openNew); n.send(.dismiss); #expect(n.phase == .idle)
    }

    @Test func whatACLaudeSessionPassesOnIsDroppedAndItsSettingsKept() {
        let env = ["CLAUDECODE": "1", "CLAUDE_CODE_CHILD_SESSION": "1", "CLAUDE_CODE_SESSION_ID": "s", "CLAUDE_PID": "26411", "CLAUDE_CODE_USE_BEDROCK": "1", "PATH": "/bin"]
        #expect(Set(env.keys.filter { NewSession.inheritedSession.contains($0) }) == ["CLAUDECODE", "CLAUDE_CODE_CHILD_SESSION", "CLAUDE_CODE_SESSION_ID", "CLAUDE_PID"])
    }

    @Test func findsTheClaudeProjectForAFolder() {
        let presets = Data("""
        {"byAccount": {"a": {"presets": [
          {"id": "1", "name": "perch", "lastUsedAt": 10, "target": {"kind": "local", "cwd": "/u/perch"}},
          {"id": "2", "name": "Law scheduling", "lastUsedAt": 5, "target": {"kind": "local", "cwd": "/u/Business/law-scheduling/"}},
          {"id": "3", "name": "perch again", "lastUsedAt": 20, "target": {"kind": "local", "cwd": "/u/perch"}},
          {"id": "4", "name": "site cloud", "target": {"kind": "cloud", "cwd": "/u/site"}}
        ]}}}
        """.utf8)
        // the most recently used of the projects on that folder
        #expect(NewSession.claudeProject(for: "/u/perch", presets: presets) == "perch again")
        #expect(NewSession.claudeProject(for: "/u/Business/law-scheduling", presets: presets) == "Law scheduling")
        // only one on this Mac; none for the folder; not Claude's file
        #expect(NewSession.claudeProject(for: "/u/site", presets: presets) == nil)
        #expect(NewSession.claudeProject(for: "/u/other", presets: presets) == nil)
        #expect(NewSession.claudeProject(for: "/u/perch", presets: Data("nope".utf8)) == nil)
    }
}
