import Testing
import Foundation
import SQLite3
@testable import PerchCore

/// A home folder with Muse Code sessions in it, in the shape Muse 1.4 writes: one envelope a line, sharded by local date,
/// and its SQLite index beside them.
private final class MuseHome {
    let url: URL
    let now = Date()
    init() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("perch-muse-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }

    var scanner: SessionScanner {
        let s = SessionScanner(home: url, desktop: DesktopSessions(root: url.appendingPathComponent("none")))
        s.usable = { FileManager.default.fileExists(atPath: $0) }
        s.lookUpGit = { _ in nil }; s.lookUpBranch = { _ in nil }; s.lookUpRepo = { _ in nil }
        return s
    }

    @discardableResult func folder(_ path: String) -> String {
        let u = url.appendingPathComponent(path)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u.path
    }

    /// A session log: the retained frame and metadata first, start-up phases for the terminal app, then `records`.
    @discardableResult func session(_ id: String, cwd: String, ago: TimeInterval = 60, interactive: Bool = true, records: [String]) -> URL {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: now.addingTimeInterval(-ago))
        let dir = url.appendingPathComponent(String(format: ".local/share/muse/sessions/%04d/%02d/%02d/%@", c.year!, c.month!, c.day!, id))
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var lines = [#"{"schema_version":1,"retained_frame":"{}"}"#,
                     envelope(id, -ago - 30, "runtime.session.metadata", #"{"kind":"metadata","record":{"workspace_root":"\#(cwd)","provider_id":"meta"}}"#)]
        if interactive { lines.append(envelope(id, -ago - 29, "session.startup_phases.observed", #"{"kind":"startup_phases"}"#)) }
        lines += records
        let f = dir.appendingPathComponent("session.jsonl")
        try? (lines.joined(separator: "\n") + "\n").data(using: .utf8)!.write(to: f)
        try? FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-ago)], ofItemAtPath: f.path)
        return f
    }

    func envelope(_ id: String, _ offset: TimeInterval, _ type: String, _ payload: String) -> String {
        let us = Int64((now.timeIntervalSince1970 + offset) * 1_000_000)
        return #"{"schema_version":1,"id":"\#(UUID().uuidString)","stream":{"kind":"session","id":"\#(id)"},"sequence":1,"recorded_at":\#(us),"record_type":"event","payload_type":"\#(type)","payload":\#(payload)}"#
    }
    func run(_ id: String, _ offset: TimeInterval, _ event: String) -> String {
        envelope(id, offset, "runtime.session", #"{"kind":"run","run_id":"r1","event":\#(event)}"#)
    }
    func prompt(_ id: String, _ offset: TimeInterval, _ text: String) -> String { run(id, offset, #"{"kind":"started","prompt":"\#(text)"}"#) }
    func said(_ id: String, _ offset: TimeInterval, _ text: String) -> String { run(id, offset, #"{"kind":"assistant_message_committed","text":"\#(text)"}"#) }
    func shell(_ id: String, _ offset: TimeInterval, _ call: String, _ command: String) -> String {
        run(id, offset, #"{"kind":"assistant_tool_calls_committed","tool_calls":[{"name":"shell","call_id":"\#(call)","args":{"cmd":"\#(command)"}}]}"#)
    }
    func result(_ id: String, _ offset: TimeInterval, _ call: String, _ text: String) -> String {
        run(id, offset, #"{"kind":"tool_result_batch_committed","results":[{"tool_call_id":"\#(call)","text":"\#(text)"}]}"#)
    }
    func end(_ id: String, _ offset: TimeInterval, _ how: String = "completed") -> String {
        run(id, offset, #"{"kind":"terminal","terminal":"\#(how)","reason":null}"#)
    }
    /// A task record in the same stream: Muse's reminders, never what you said.
    func task(_ id: String, _ offset: TimeInterval) -> String {
        envelope(id, offset, "runtime.session", #"{"kind":"task","run_id":"r1","task_id":"t1","event":{"kind":"started","task_id":"t1"}}"#)
    }

    func index(_ titles: [String: String]) {
        let f = url.appendingPathComponent(".local/share/muse/session-index.db")
        var db: OpaquePointer?
        sqlite3_open(f.path, &db); defer { sqlite3_close(db) }
        sqlite3_exec(db, "CREATE TABLE sessions (session_id TEXT, title TEXT, effective_long_title TEXT)", nil, nil, nil)
        for (id, t) in titles { sqlite3_exec(db, "INSERT INTO sessions VALUES ('\(id)', 'first prompt', '\(t)')", nil, nil, nil) }
    }
}

@Suite struct MuseScanTests {
    @Test func museSessionsAreListedByTheirTitleOrFirstPrompt() {
        let h = MuseHome(), site = h.folder("code/ledger")
        h.session("m1", cwd: site, ago: 60, records: [
            h.prompt("m1", -90, "split the ledger export into one file per account"), h.task("m1", -89),
            h.shell("m1", -85, "c1", "cargo test"), h.result("m1", -80, "c1", "ok"),
            h.said("m1", -75, "The export now writes one file per account."), h.end("m1", -74),
        ])
        h.session("m2", cwd: site, ago: 120, records: [
            h.prompt("m2", -150, "add a progress bar to the export"), h.shell("m2", -145, "c1", "cargo build"), h.result("m2", -140, "c1", "ok"),
            h.said("m2", -135, "The export shows a progress bar."), h.end("m2", -134),
        ])
        h.index(["m2": "Progress bar for the export"])
        let found = h.scanner.muse(limit: 15, now: h.now).map(\.project)
        #expect(found.map(\.sessionId) == ["m1", "m2"])
        #expect(found.map(\.topic) == ["split the ledger export into one file per account", "Progress bar for the export"])
        #expect(found.first?.app == "muse"); #expect(found.first?.terminal == true)
        #expect(found.first?.status.text == "Muse replied")
        #expect(found.first?.said == "The export now writes one file per account.")
    }

    @Test func museStatusFollowsTheTurn() {
        let h = MuseHome(), site = h.folder("code/ledger")
        h.session("work", cwd: site, ago: 2, records: [h.prompt("work", -10, "run the whole test suite please"), h.shell("work", -5, "c1", "cargo test --all")])
        h.session("stop", cwd: site, ago: 60, records: [h.prompt("stop", -90, "run the whole test suite please"), h.shell("stop", -85, "c1", "cargo test"),
                                                        h.end("stop", -70, "cancelled")])
        h.session("fail", cwd: site, ago: 120, records: [h.prompt("fail", -150, "run the whole test suite please"), h.shell("fail", -145, "c1", "cargo test"),
                                                         h.result("fail", -140, "c1", "ok"), h.run("fail", -130, #"{"kind":"terminal","terminal":"failed","reason":"model unavailable"}"#)])
        let by = Dictionary(uniqueKeysWithValues: h.scanner.muse(limit: 15, now: h.now).map { ($0.project.sessionId ?? "", $0.project) })
        #expect(by["work"]?.status.kind == "running"); #expect(by["work"]?.now == "Running `cargo test --all`")
        #expect(by["stop"]?.status.text == "You stopped Muse")
        #expect(by["fail"]?.status.text == "Muse stopped on an error"); #expect(by["fail"]?.context == "model unavailable")
        // a turn end Muse adds later reads as a plain end, never an error
        h.session("new", cwd: site, ago: 200, records: [h.prompt("new", -230, "run the whole test suite please"), h.shell("new", -225, "c1", "cargo test"),
                                                        h.result("new", -222, "c1", "ok"), h.said("new", -221, "All green."), h.run("new", -220, #"{"kind":"terminal","terminal":"handed_off"}"#)])
        #expect(h.scanner.muse(limit: 15, now: h.now).first { $0.project.sessionId == "new" }?.project.status.text == "Muse replied")
    }

    @Test func headlessRunsAndGoneFoldersGetNoRow() {
        let h = MuseHome(), site = h.folder("code/ledger")
        h.session("exec", cwd: site, ago: 30, interactive: false, records: [h.prompt("exec", -40, "summarise the changelog for me"), h.shell("exec", -38, "c1", "cat CHANGELOG.md"),
                                                                            h.result("exec", -37, "c1", "ok"), h.said("exec", -36, "Three fixes."), h.end("exec", -35)])
        h.session("gone", cwd: h.url.path + "/code/deleted", ago: 20, records: [h.prompt("gone", -30, "make the export retry three times"), h.shell("gone", -25, "c1", "cargo test")])
        #expect(h.scanner.muse(limit: 15, now: h.now).isEmpty)
    }

    @Test func aPullRequestMuseOpenedIsFoundInItsLog() {
        let h = MuseHome(), site = h.folder("code/ledger")
        let pr = "https://github.com/asafofer/ledger/pull/12"
        h.session("pr", cwd: site, ago: 30, records: [
            h.prompt("pr", -60, "open a pull request for the export split"), h.shell("pr", -50, "c9", "gh pr create --fill"),
            h.result("pr", -45, "c9", pr + "\\n"), h.said("pr", -40, "Opened the pull request."), h.end("pr", -39),
        ])
        let p = h.scanner.muse(limit: 15, now: h.now).first?.project
        #expect(p?.prs.map(\.url) == [pr])
    }

    @Test func museIsRecognisedByItsBinary() {
        #expect(Agent.recognise(executable: "/Users/a/.local/bin/muse-bin-1.4.14-R7309.1", argv0: nil) == .muse)
        #expect(Agent.mayBe("/Users/a/.local/bin/muse-bin-1.4.14-R7309.1"))
        #expect(Agent.muse.resume("01a1") == "muse resume 01a1")
        #expect(!Agent.muse.resumeTakesPrompt && !Agent.muse.answersFromNotch)
    }

    @Test func museNotificationSaysItWaitsOnYou() {
        let body = Data(#"{"hook_event_name":"Notification","session_id":"01a1","notification_type":"permission_prompt","message":"Muse Code needs approval"}"#.utf8)
        let e = HookEvent.parse(agent: "muse", event: "Notification", body: body, requestId: "r1")
        guard case .asks(let a)? = e?.kind else { Issue.record("no ask"); return }
        #expect(a.kind == .permission); #expect(a.title == "Muse wants your OK"); #expect(!a.answerable)
        let q = HookEvent.parse(agent: "muse", event: "Notification", body: Data(#"{"session_id":"01a1","notification_type":"question_prompt"}"#.utf8), requestId: "r2")
        guard case .asks(let b)? = q?.kind else { Issue.record("no question"); return }
        #expect(b.kind == .question); #expect(!b.answerable)
        // Another agent's Notification, and Muse's other kinds (idle, auth), are not requests.
        #expect(HookEvent.parse(agent: "claude", event: "Notification", body: body, requestId: "r3") == nil)
        #expect(HookEvent.parse(agent: "muse", event: "Notification", body: Data(#"{"session_id":"01a1","notification_type":"idle_prompt"}"#.utf8), requestId: "r4") == nil)
    }

    @Test func newMuseSessionStartsWithYourWords() {
        #expect(NewSession.command(agent: "muse", prompt: "fix it's export") == #"muse 'fix it'\''s export'"#)
        #expect(NewSession.choices(claudeApp: false, codexApp: false, commands: ["muse"]).map(\.id) == ["muse"])
    }
}
