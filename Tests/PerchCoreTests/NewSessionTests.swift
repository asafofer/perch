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
        // a model chosen goes to each agent as it takes one; the default, or an agent that takes none, adds nothing
        #expect(NewSession.command(agent: "claude", prompt: "go", sessionId: "abc", model: "fable") == "claude --model 'fable' --session-id abc 'go'")
        #expect(NewSession.command(agent: "codex", prompt: "go", model: "gpt-6-sol") == "codex -m 'gpt-6-sol' 'go'")
        #expect(NewSession.command(agent: "opencode", prompt: "go", model: "openai/gpt-6") == "opencode --model 'openai/gpt-6' --prompt 'go'")
        #expect(NewSession.command(agent: "claude", prompt: "go", model: "") == "claude 'go'")
        #expect(NewSession.command(agent: "pi", prompt: "go", model: "x") == "pi 'go'")
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

    @Test func modelsStartWithTheDefaultThenTheAgentsOwnNames() {
        let claude = NewSession.models(agent: "claude", configured: "opus", used: ["claude-fable-5-1", "opus"])
        #expect(claude.map(\.id) == ["", "fable", "opus", "sonnet", "haiku", "claude-fable-5-1"])
        #expect(claude.first == NewSession.Model(id: "", name: "Default", note: "opus"))
        #expect(NewSession.models(agent: "opencode", configured: nil, available: ["openai/gpt-6", "lmstudio/qwen"]).map(\.id) == ["", "openai/gpt-6", "lmstudio/qwen"])
        #expect(NewSession.models(agent: "codex", configured: "gpt-6-sol", used: ["gpt-6-mini"]).map(\.id) == ["", "gpt-6-mini"])
        #expect(NewSession.models(agent: "pi", configured: nil).isEmpty)
    }

    @Test func readsEachAgentsDefaultModel() {
        #expect(NewSession.claudeDefault(settings: Data(#"{"model":"opus","hooks":{}}"#.utf8)) == "opus")
        #expect(NewSession.claudeDefault(settings: Data(#"{"hooks":{}}"#.utf8)) == nil)
        #expect(NewSession.codexDefault(config: "# mine\nmodel = \"gpt-6-sol\" # fast\napproval = \"never\"\n[profiles.deep]\nmodel = \"gpt-6\"") == "gpt-6-sol")
        #expect(NewSession.codexDefault(config: "model_provider = \"openai\"\n[profiles.deep]\nmodel = \"gpt-6\"") == nil)
        #expect(NewSession.opencodeModels("github-copilot/claude-fable-5.1\nopenai/gpt-6\n\nUpdating models...") == ["github-copilot/claude-fable-5.1", "openai/gpt-6"])
    }
}
