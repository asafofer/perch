import Testing
import Foundation
import SQLite3
@testable import PerchCore

/// A home folder with Conductor's database in it (the tables and columns it writes), and the transcripts its agents leave.
private final class ConductorHome {
    let url: URL
    let now = Date()
    private var db: OpaquePointer?
    init() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("perch-conductor-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        sqlite3_open(database.path, &db)
        sql("""
            CREATE TABLE repos (id TEXT, name TEXT, root_path TEXT);
            CREATE TABLE workspaces (id TEXT, repository_id TEXT, branch TEXT, state TEXT DEFAULT 'ready', workspace_path TEXT);
            CREATE TABLE sessions (id TEXT, claude_session_id TEXT, agent_type TEXT, title TEXT DEFAULT 'Untitled', workspace_id TEXT,
                                   is_hidden INTEGER DEFAULT 0, remote_archived_at TEXT);
            INSERT INTO repos VALUES ('r1', 'site', '/somewhere/site');
            """)
    }
    deinit { sqlite3_close(db); try? FileManager.default.removeItem(at: url) }

    var database: URL { url.appendingPathComponent("conductor.db") }
    var scanner: SessionScanner {
        let s = SessionScanner(home: url, desktop: DesktopSessions(root: url.appendingPathComponent("none")), conductor: ConductorSessions(database: database))
        s.usable = { FileManager.default.fileExists(atPath: $0) }
        s.lookUpGit = { _ in nil }; s.lookUpBranch = { _ in nil }; s.lookUpRepo = { _ in nil }
        return s
    }

    private func sql(_ s: String) {
        var err: UnsafeMutablePointer<CChar>?
        sqlite3_exec(db, s, nil, nil, &err)
        if let err { Issue.record(Comment(rawValue: String(cString: err))) }
    }
    private func write(_ path: String, _ text: String, ago: TimeInterval) {
        let u = url.appendingPathComponent(path)
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.data(using: .utf8)!.write(to: u)
        try? FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-ago)], ofItemAtPath: u.path)
    }

    /// A workspace: a worktree folder, its row, and one session row in it. Returns the folder.
    @discardableResult func workspace(_ id: String, session: String, agent: String = "claude", title: String = "Untitled", state: String = "ready",
                                      hidden: Bool = false) -> String {
        let folder = url.appendingPathComponent("conductor/workspaces/site/\(id)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        sql("""
            INSERT INTO workspaces VALUES ('\(id)', 'r1', 'asaf/\(id)', '\(state)', '\(folder.path)');
            INSERT INTO sessions VALUES ('s-\(id)', '\(session)', '\(agent)', '\(title)', '\(id)', \(hidden ? 1 : 0), NULL);
            """)
        return folder.path
    }

    /// What Claude Code leaves for a Conductor session: the SDK's entrypoint, and Conductor's instructions ahead of your prompt.
    func claudeTranscript(_ id: String, cwd: String, ago: TimeInterval = 60) {
        let ts = ISO8601DateFormatter().string(from: now.addingTimeInterval(-ago))
        let prompt = "<system_instruction>\\nYou are working inside Conductor, a Mac app.\\n</system_instruction>\\n\\ntighten the hero spacing"
        let lines = [
            #"{"type":"user","sessionId":"\#(id)","cwd":"\#(cwd)","entrypoint":"sdk-ts","timestamp":"\#(ts)","message":{"content":"\#(prompt)"}}"#,
            #"{"type":"assistant","sessionId":"\#(id)","cwd":"\#(cwd)","entrypoint":"sdk-ts","timestamp":"\#(ts)","message":{"stop_reason":"tool_use","content":[{"type":"tool_use","id":"t1","name":"Edit","input":{"file_path":"/x/hero.css"}}]}}"#,
            #"{"type":"user","sessionId":"\#(id)","cwd":"\#(cwd)","entrypoint":"sdk-ts","timestamp":"\#(ts)","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]}}"#,
            #"{"type":"assistant","sessionId":"\#(id)","cwd":"\#(cwd)","entrypoint":"sdk-ts","timestamp":"\#(ts)","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"The hero now fits at phone width."}]}}"#,
        ]
        let folder = String(cwd.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
        write(".claude/projects/\(folder)/\(id).jsonl", lines.joined(separator: "\n") + "\n", ago: ago)
    }

    /// What Codex leaves for a Conductor thread: the SDK's originator, `vscode` as its source.
    func codexRollout(_ id: String, cwd: String, ago: TimeInterval = 60) {
        let ts = ISO8601DateFormatter().string(from: now.addingTimeInterval(-ago))
        let lines = [
            #"{"type":"session_meta","payload":{"id":"\#(id)","cwd":"\#(cwd)","originator":"codex_sdk_ts","source":"vscode"}}"#,
            #"{"timestamp":"\#(ts)","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<system_instruction>\nYou are working inside Conductor.\n</system_instruction>"}]}}"#,
            #"{"timestamp":"\#(ts)","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"rewrite the install guide so setup comes first"}]}}"#,
            #"{"timestamp":"\#(ts)","type":"response_item","payload":{"type":"function_call","name":"shell","arguments":"{}"}}"#,
            #"{"timestamp":"\#(ts)","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Moved setup above troubleshooting."}]}}"#,
        ]
        write(".codex/sessions/2026/10/12/rollout-\(id).jsonl", lines.joined(separator: "\n") + "\n", ago: ago)
    }
}

@Suite struct ConductorScanTests {
    @Test func aWorkspaceSessionGetsARowThatOpensInConductor() {
        let h = ConductorHome()
        let cwd = h.workspace("ws-1", session: "abc", title: "Hero spacing")
        h.claudeTranscript("abc", cwd: cwd)
        let found = h.scanner.claude(limit: 15, now: h.now)
        #expect(found.count == 1)
        let p = found.first?.project
        #expect(p?.conductor == "ws-1")
        #expect(p?.app == "claude")
        #expect(p?.terminal == false)
        #expect(p?.name == "site")                      // Conductor's project, not the worktree's made-up folder name
        #expect(p?.topic == "Hero spacing")             // its own title for the session
        #expect(p?.branch == "asaf/ws-1")
        #expect(p?.said == "The hero now fits at phone width.")
    }

    @Test func conductorsInstructionsAreNotYourPrompt() {
        let h = ConductorHome()
        let cwd = h.workspace("ws-1", session: "abc")   // no title yet: the prompt names the row
        h.claudeTranscript("abc", cwd: cwd)
        let p = h.scanner.claude(limit: 15, now: h.now).first?.project
        #expect(p?.asked == "tighten the hero spacing")
        #expect(p?.topic == "tighten the hero spacing")
    }

    @Test func archivedWorkspacesHiddenSessionsAndOtherAgentsAreLeftOut() {
        let h = ConductorHome()
        for (id, session, agent, state, hidden) in [("ws-1", "a", "claude", "ready", false), ("ws-2", "b", "claude", "archived", false),
                                                    ("ws-3", "c", "claude", "ready", true), ("ws-4", "d", "cursor", "ready", false)] {
            h.claudeTranscript(session, cwd: h.workspace(id, session: session, agent: agent, state: state, hidden: hidden))
        }
        #expect(h.scanner.claude(limit: 15, now: h.now).compactMap(\.project.conductor) == ["ws-1"])
    }

    @Test func aTranscriptConductorListsIsNotAlsoATerminalSession() {
        let h = ConductorHome()
        h.claudeTranscript("abc", cwd: h.workspace("ws-1", session: "abc"))
        #expect(h.scanner.claude(limit: 15, now: h.now).filter(\.project.terminal).isEmpty)
        // Without Conductor's record the same transcript (an SDK run) is not a session to go back to.
        try? FileManager.default.removeItem(at: h.database)
        #expect(h.scanner.claude(limit: 15, now: h.now).isEmpty)
    }

    @Test func aCodexThreadConductorRunsOpensInConductorNotInCodex() {
        let h = ConductorHome()
        let cwd = h.workspace("ws-1", session: "thread-1", agent: "codex", title: "Install guide")
        h.codexRollout("thread-1", cwd: cwd)
        let p = h.scanner.codex(limit: 15, now: h.now).first?.project
        #expect(p?.conductor == "ws-1")
        #expect(p?.app == "codex")
        #expect(p?.topic == "Install guide")
        #expect(p?.name == "site")
    }

    @Test func anArchivedConductorCodexThreadDoesNotComeBackAsACodexAppThread() {
        let h = ConductorHome()
        h.codexRollout("thread-1", cwd: h.workspace("ws-1", session: "thread-1", agent: "codex", state: "archived"))
        #expect(h.scanner.codex(limit: 15, now: h.now).isEmpty)
    }

    @Test func aMissingOrUnreadableDatabaseIsNoSessions() {
        let h = ConductorHome()
        try? FileManager.default.removeItem(at: h.database)
        #expect(ConductorSessions(database: h.database).index().isEmpty)
        try? "not a database".write(to: h.database, atomically: true, encoding: .utf8)
        #expect(ConductorSessions(database: h.database).index().isEmpty)
    }

    @Test func aNewerConductorWithoutTheHiddenColumnsStillListsItsSessions() {
        let h = ConductorHome()
        let path = h.database.path
        var db: OpaquePointer?
        sqlite3_open(path, &db)
        sqlite3_exec(db, """
            DROP TABLE sessions;
            CREATE TABLE sessions (id TEXT, claude_session_id TEXT, agent_type TEXT, title TEXT, workspace_id TEXT);
            INSERT INTO workspaces VALUES ('ws-1', 'r1', 'b', 'ready', '/w');
            INSERT INTO sessions VALUES ('s1', 'abc', 'claude', 'Hero', 'ws-1');
            """, nil, nil, nil)
        sqlite3_close(db)
        #expect(ConductorSessions(database: h.database).index()["abc"]?.workspaceId == "ws-1")
    }
}
