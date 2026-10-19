import Testing
import Foundation
@testable import PerchCore

/// A home folder on disk with Claude app sessions, Claude Code transcripts and Codex threads in it.
private final class Home {
    let url: URL
    let now = Date()
    init() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("perch-scan-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }

    var scanner: SessionScanner {
        let s = SessionScanner(home: url, desktop: DesktopSessions(root: url.appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")))
        s.usable = { FileManager.default.fileExists(atPath: $0) }
        s.lookUpGit = { _ in nil }; s.lookUpBranch = { _ in nil }; s.lookUpRepo = { _ in nil }
        return s
    }

    @discardableResult func folder(_ path: String) -> String {
        let u = url.appendingPathComponent(path)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u.path
    }

    func write(_ path: String, _ text: String, ago: TimeInterval = 60) {
        let u = url.appendingPathComponent(path)
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.data(using: .utf8)!.write(to: u)
        try? FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-ago)], ofItemAtPath: u.path)
    }

    /// A Claude app session: its entry in the app's list and its transcript where Claude Code keeps it.
    func claude(_ cli: String, cwd: String, title: String, ago: TimeInterval = 60, archived: Bool = false, dir: String? = nil,
                spawnedFrom: [String: Any]? = nil) {
        var entry: [String: Any] = ["sessionId": "local_\(cli)", "cliSessionId": cli, "cwd": cwd, "title": title, "isArchived": archived,
                                    "lastFocusedAt": (now.timeIntervalSince1970 - ago - 30) * 1000]
        if let spawnedFrom { entry["spawnedFrom"] = spawnedFrom }
        write("Library/Application Support/Claude/claude-code-sessions/acct/org/local_\(cli).json",
              String(data: try! JSONSerialization.data(withJSONObject: entry), encoding: .utf8)!)
        let folder = dir ?? String(cwd.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
        write(".claude/projects/\(folder)/\(cli).jsonl", Self.transcript(cli, cwd: cwd, at: now.addingTimeInterval(-ago)), ago: ago)
    }

    /// `entrypoint`: "claude-desktop" for the app, "cli" for a terminal, "sdk-cli" for `claude -p`.
    static func transcript(_ id: String, cwd: String, at: Date, entrypoint: String = "claude-desktop") -> String {
        let ts = ISO8601DateFormatter().string(from: at)
        return [
            #"{"type":"user","sessionId":"\#(id)","cwd":"\#(cwd)","entrypoint":"\#(entrypoint)","timestamp":"\#(ts)","message":{"content":"tighten the hero spacing on the landing page"}}"#,
            #"{"type":"assistant","sessionId":"\#(id)","cwd":"\#(cwd)","timestamp":"\#(ts)","message":{"stop_reason":"tool_use","content":[{"type":"tool_use","id":"t1","name":"Edit","input":{"file_path":"/x/hero.css"}}]}}"#,
            #"{"type":"user","sessionId":"\#(id)","cwd":"\#(cwd)","timestamp":"\#(ts)","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]}}"#,
            #"{"type":"assistant","sessionId":"\#(id)","cwd":"\#(cwd)","timestamp":"\#(ts)","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"The hero now fits at phone width."}]}}"#,
        ].joined(separator: "\n") + "\n"
    }

    /// A Codex thread. `source` is how it started: "vscode" for the app, "exec" for a headless run.
    func codex(_ id: String, cwd: String, day: String = "2026/10/09", source: String = #""vscode""#, originator: String = "Codex Desktop",
               ago: TimeInterval = 60, instructions: String = "") {
        let ts = ISO8601DateFormatter().string(from: now.addingTimeInterval(-ago))
        let lines = [
            #"{"type":"session_meta","payload":{"id":"\#(id)","cwd":"\#(cwd)","originator":"\#(originator)","source":\#(source),"base_instructions":"\#(instructions)"}}"#,
            #"{"timestamp":"\#(ts)","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"rewrite the install guide so setup comes first"}]}}"#,
            #"{"timestamp":"\#(ts)","type":"response_item","payload":{"type":"function_call","name":"shell","arguments":"{}"}}"#,
            #"{"timestamp":"\#(ts)","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Moved setup above troubleshooting."}]}}"#,
        ]
        write(".codex/sessions/\(day)/rollout-\(id).jsonl", lines.joined(separator: "\n") + "\n", ago: ago)
    }
}

@Suite struct SessionScanTests {
    @Test func aHelperAtWorkInTheBackgroundKeepsItsSessionAtWork() {
        let h = Home(), site = h.folder("code/site")
        let ts = ISO8601DateFormatter().string(from: h.now.addingTimeInterval(-3000))
        // The turn started a helper in the background and ended; the transcript has been still for 50 minutes since.
        let lines = [
            #"{"type":"user","sessionId":"a","cwd":"\#(site)","timestamp":"\#(ts)","message":{"content":"launch the M4 work in parallel"}}"#,
            #"{"type":"assistant","sessionId":"a","timestamp":"\#(ts)","message":{"stop_reason":"tool_use","content":[{"type":"tool_use","id":"t1","name":"Agent","input":{"description":"M4","prompt":"go","run_in_background":true}}]}}"#,
            #"{"type":"user","sessionId":"a","timestamp":"\#(ts)","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"Async agent launched successfully."}]},"toolUseResult":{"isAsync":true,"status":"async_launched","agentId":"ab12"}}"#,
            #"{"type":"assistant","sessionId":"a","timestamp":"\#(ts)","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"M4 is under way in the background."}]}}"#,
        ]
        h.claude("a", cwd: site, title: "Launch parallel M4 work", ago: 3000)
        let dir = ".claude/projects/" + String(site.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
        h.write("\(dir)/a.jsonl", lines.joined(separator: "\n") + "\n", ago: 3000)
        #expect(h.scanner.claude(limit: 15, now: h.now).first?.project.status.kind == "done")   // nothing has moved for 50 minutes
        // The helper writes its own transcript as it works: the session is at work.
        h.write("\(dir)/a/subagents/agent-ab12.jsonl", #"{"type":"assistant"}"# + "\n", ago: 20)
        let p = h.scanner.claude(limit: 15, now: h.now).first?.project
        #expect(p?.status.kind == "running"); #expect(p?.now == "Waiting on a helper: M4")
    }

    @Test func everyAppSessionGetsARowEvenInTheSameFolder() {
        let h = Home(), site = h.folder("code/site")
        h.claude("a", cwd: site, title: "Hero spacing", ago: 60)
        h.claude("b", cwd: site, title: "Footer links", ago: 120)
        let found = h.scanner.claude(limit: 15, now: h.now)
        #expect(found.map(\.project.topic) == ["Hero spacing", "Footer links"])
        #expect(found.first?.project.desktopSessionId == "local_a")
        #expect(found.first?.project.focusedAt != nil)
        #expect(found.first?.project.said == "The hero now fits at phone width.")
    }

    @Test func aSessionKeepsItsFolderWhenTheAgentChangesDirectory() {
        let h = Home(), site = h.folder("code/site"), ui = h.folder("code/site/ui")
        h.claude("a", cwd: site, title: "Hero spacing")
        // The agent ran `cd ui`: the transcript's newest lines carry the subfolder.
        let path = h.url.appendingPathComponent(".claude/projects/" + String(site.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" }) + "/a.jsonl")
        h.write(path.path.replacingOccurrences(of: h.url.path + "/", with: ""), Home.transcript("a", cwd: ui, at: h.now))
        #expect(h.scanner.claude(limit: 15, now: h.now).first?.project.name == "site")
    }
    @Test func terminalSessionsAreListedAndHeadlessRunsAreNot() {
        let h = Home(), api = h.folder("code/api"), site = h.folder("code/site")
        h.claude("app", cwd: site, title: "Hero spacing", ago: 300)
        h.write(".claude/projects/-code-api/term.jsonl", Home.transcript("term", cwd: api, at: h.now.addingTimeInterval(-60), entrypoint: "cli"), ago: 60)
        h.write(".claude/projects/-code-api/headless.jsonl", Home.transcript("headless", cwd: api, at: h.now, entrypoint: "sdk-cli"), ago: 10)
        // a session the app deleted: its transcript stays behind, but it is not a terminal session
        h.write(".claude/projects/-code-site/gone.jsonl", Home.transcript("gone", cwd: site, at: h.now), ago: 20)
        let found = h.scanner.claude(limit: 15, now: h.now).sorted { $0.last > $1.last }.map(\.project)
        #expect(found.map(\.sessionId) == ["term", "app"])
        #expect(found.first?.terminal == true); #expect(found.first?.desktopSessionId == nil)
        #expect(found.last?.terminal == false)
    }

    @Test func smallTalkInATerminalIsFoundButMarked() {
        // "hello" in a terminal: listed only while its agent still runs there (the app drops it otherwise), so the row the
        // notch just spoke of does not vanish the moment the reply lands. The Claude app's small talk stays out.
        let h = Home(), code = h.folder("code"), site = h.folder("code/site")
        let ts = ISO8601DateFormatter().string(from: h.now.addingTimeInterval(-30))
        h.write(".claude/projects/-code/hello.jsonl", [
            #"{"type":"user","sessionId":"hello","cwd":"\#(code)","entrypoint":"cli","timestamp":"\#(ts)","message":{"content":"hello"}}"#,
            #"{"type":"assistant","sessionId":"hello","cwd":"\#(code)","timestamp":"\#(ts)","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"Hi! What can I help you with today?"}]}}"#,
        ].joined(separator: "\n") + "\n", ago: 30)
        h.write(".claude/projects/-code-site/work.jsonl", Home.transcript("work", cwd: site, at: h.now.addingTimeInterval(-60), entrypoint: "cli"), ago: 60)
        let found = h.scanner.claude(limit: 1, now: h.now).map(\.project)
        #expect(found.map(\.sessionId) == ["hello", "work"])   // small talk takes no place of a real session
        #expect(found.map(\.smallTalk) == [true, false])
    }

    @Test func codexInATerminalIsATerminalSession() {
        let h = Home(), docs = h.folder("code/docs")
        h.codex("cli1", cwd: docs, source: #""cli""#, originator: "codex_cli_rs", ago: 60)
        h.codex("app1", cwd: docs, ago: 120)
        // Codex 0.162's terminal app writes the app's source; its originator gives it away.
        h.codex("tui1", cwd: docs, source: #""vscode""#, originator: "codex-tui", ago: 30)
        let found = h.scanner.codex(limit: 15, now: h.now).map(\.project)
        #expect(found.map(\.sessionId) == ["tui1", "cli1", "app1"])
        #expect(found.map(\.terminal) == [true, true, false])
    }

    @Test func theLastMessageKeepsItsLineBreaks() {
        let h = Home(), site = h.folder("code/site")
        h.claude("a", cwd: site, title: "Hero spacing")
        let path = ".claude/projects/" + String(site.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" }) + "/a.jsonl"
        let said = #"{"type":"assistant","sessionId":"a","cwd":"\#(site)","timestamp":"\#(ISO8601DateFormatter().string(from: h.now))","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"Done.\n\n- one\n- two\n\nWant more?"}]}}"#
        h.write(path, Home.transcript("a", cwd: site, at: h.now.addingTimeInterval(-60)) + said + "\n")
        let p = h.scanner.claude(limit: 15, now: h.now).first?.project
        #expect(p?.said == "Done.\n\n- one\n- two\n\nWant more?")
        #expect(p?.context.contains("\n") == false)   // summaries stay on one line
    }

    @Test func yourLastMessageKeepsItsLineBreaks() {
        let h = Home(), site = h.folder("code/site")
        h.claude("a", cwd: site, title: "Hero spacing")
        let path = ".claude/projects/" + String(site.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" }) + "/a.jsonl"
        let ts = ISO8601DateFormatter().string(from: h.now)
        let you = #"{"type":"user","sessionId":"a","cwd":"\#(site)","timestamp":"\#(ts)","message":{"role":"user","content":"Make the hero fit.\n\nKeep the poster."}}"#
        let said = #"{"type":"assistant","sessionId":"a","cwd":"\#(site)","timestamp":"\#(ts)","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"Done."}]}}"#
        h.write(path, Home.transcript("a", cwd: site, at: h.now.addingTimeInterval(-60)) + you + "\n" + said + "\n")
        let p = h.scanner.claude(limit: 15, now: h.now).first?.project
        #expect(p?.asked == "Make the hero fit.\n\nKeep the poster.")
        #expect(p?.said == "Done.")
    }

    @Test func archivedSessionsAreLeftOut() {
        let h = Home(), site = h.folder("code/site")
        h.claude("a", cwd: site, title: "Hero spacing")
        h.claude("b", cwd: site, title: "Old idea", archived: true)
        #expect(h.scanner.claude(limit: 15, now: h.now).map(\.project.topic) == ["Hero spacing"])
    }

    /// A side chat is a copy of its session's transcript, so as a row it reads just like that session, and a reply to it
    /// lands in the side chat. A session started from another (start_session) is a session of its own and keeps its row.
    @Test func sideChatsAreLeftOut() {
        let h = Home(), site = h.folder("code/site")
        h.claude("a", cwd: site, title: "Hero spacing")
        h.claude("b", cwd: site, title: "Side chat", spawnedFrom: ["sessionId": "local_a", "sideSession": true, "userFork": true, "btw": true])
        h.claude("c", cwd: site, title: "Footer links", spawnedFrom: ["sessionId": "local_a", "taskId": "task_1"])
        #expect(Set(h.scanner.claude(limit: 15, now: h.now).map(\.project.topic)) == ["Hero spacing", "Footer links"])
    }

    @Test func busyFoldersCannotCrowdOutAnAppSession() {
        let h = Home(), finance = h.folder("code/finance")
        h.claude("app", cwd: finance, title: "September invoices", ago: 3 * 3600)
        // Twenty newer folders of headless runs (`claude -p`) the Claude app does not list.
        for i in 0..<20 { h.write(".claude/projects/-other-\(i)/run\(i).jsonl", Home.transcript("run\(i)", cwd: h.folder("code/o\(i)"), at: h.now, entrypoint: "sdk-cli"), ago: 10) }
        #expect(h.scanner.claude(limit: 15, now: h.now).map(\.project.topic) == ["September invoices"])
    }

    @Test func aTranscriptInAnUnexpectedFolderIsStillFound() {
        let h = Home(), site = h.folder("code/site")
        h.claude("a", cwd: site, title: "Hero spacing", dir: "-some-truncated-name-1a2b3c")
        #expect(h.scanner.claude(limit: 15, now: h.now).count == 1)
    }

    @Test func aChatWithoutAProjectIsNamedByItsTitle() {
        let h = Home(), scratch = h.folder("Library/Application Support/Claude/scratch-workspaces/u/o/scratch-2026-10-09-ab78ac")
        h.claude("a", cwd: scratch, title: "JSON Hero Raycast extension")
        let p = h.scanner.claude(limit: 15, now: h.now).first?.project
        #expect(p?.name == "JSON Hero Raycast extension"); #expect(p?.topic == "")
    }

    @Test func onlyCodexThreadsYouStarted() {
        let h = Home(), docs = h.folder("code/docs")
        h.codex("app1", cwd: docs, ago: 300)
        h.codex("exec1", cwd: docs, source: #""exec""#, originator: "codex_exec", ago: 60)
        h.codex("sub1", cwd: docs, source: #"{"subagent":{"thread_spawn":{}}}"#, ago: 30)
        h.write(".codex/session_index.jsonl", #"{"id":"app1","thread_name":"Install guide","updated_at":"2026-10-09T10:00:00Z"}"# + "\n")
        let found = h.scanner.codex(limit: 15, now: h.now)
        #expect(found.map(\.project.sessionId) == ["app1"])
        #expect(found.first?.project.topic == "Install guide")
    }

    @Test func aResumedThreadInAnOldDayFolderIsFound() {
        let h = Home(), docs = h.folder("code/docs")
        h.codex("old", cwd: docs, day: "2025/01/01", ago: 120)
        #expect(h.scanner.codex(limit: 15, now: h.now).map(\.project.sessionId) == ["old"])
    }

    @Test func aLongHebrewFirstLineStillReads() {
        // The first line is longer than the old 200 KB read and cut through a two-byte letter there.
        let h = Home(), docs = h.folder("code/docs")
        h.codex("he", cwd: docs, instructions: String(repeating: "\u{05D0}", count: 150_001))
        #expect(h.scanner.codex(limit: 15, now: h.now).map(\.project.sessionId) == ["he"])
    }

    @Test func aTailThatStartsInsideALetterStillReads() throws {
        let h = Home(), site = h.folder("code/site")
        let filler = #"{"type":"system","note":""# + String(repeating: "\u{05D0}", count: 5000) + #""}"#
        let body = filler + "\n" + Home.transcript("a", cwd: site, at: h.now)
        h.write(".claude/projects/x/a.jsonl", body)
        let url = h.url.appendingPathComponent(".claude/projects/x/a.jsonl")
        let data = try Data(contentsOf: url)
        // A window whose first byte is the second half of a Hebrew letter.
        let start = try #require((100..<9000).first { (data[$0] & 0xC0) == 0x80 })
        let d = SessionScanner.digest(of: url, windows: [UInt64(data.count - start)], parse: TranscriptParser.digest)
        #expect(d?.lastUserText == "tighten the hero spacing on the landing page")
    }
}

@Suite struct GitLookUpTests {
    @Test func aStatusLongerThanAPipeHoldsIsRead() throws {
        // A checkout with thousands of changes prints more than a pipe holds (64 KB). Read only after git had exited, git
        // waited for room that never came, the first scan never ended, and the list stayed on "Looking for your sessions".
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("perch-git-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let git = Process(); git.executableURL = URL(fileURLWithPath: "/usr/bin/env"); git.arguments = ["git", "-C", dir.path, "init", "-q"]
        try git.run(); git.waitUntilExit()
        for i in 0..<4000 { FileManager.default.createFile(atPath: dir.appendingPathComponent("untracked-file-\(i).txt").path, contents: nil) }
        #expect(SessionScanner.git(at: dir.path)?.uncommitted == 4000)
    }
}
