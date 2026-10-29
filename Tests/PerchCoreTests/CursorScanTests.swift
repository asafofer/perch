import Testing
import Foundation
import SQLite3
@testable import PerchCore

/// A home folder with Cursor's database and agent transcripts in it, in the formats Cursor writes.
private final class CursorHome {
    let url: URL
    let now = Date()
    private var db: OpaquePointer?
    private var withDatabase: Bool
    /// A Cursor from before the `composerHeaders` table: only `cursorDiskKV`.
    private let headers: Bool
    init(database: Bool = true, headers: Bool = true) {
        self.headers = headers
        url = FileManager.default.temporaryDirectory.appendingPathComponent("perch-cursor-\(UUID().uuidString)")
        withDatabase = database
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { sqlite3_close(db); try? FileManager.default.removeItem(at: url) }

    /// How Cursor names a transcript folder after a path: dots dropped, every other symbol a dash.
    static func slug(_ path: String) -> String {
        String(path.dropFirst().replacingOccurrences(of: ".", with: "").map { $0.isLetter && $0.isASCII || $0.isNumber ? $0 : "-" })
    }

    var user: URL { url.appendingPathComponent("Library/Application Support/Cursor/User") }

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

    private func sql(_ s: String) {
        if db == nil {
            let dir = user.appendingPathComponent("globalStorage")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            sqlite3_open(dir.appendingPathComponent("state.vscdb").path, &db)
            sqlite3_exec(db, """
                CREATE TABLE cursorDiskKV (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB);
                CREATE TABLE ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB);
                """ + (headers ? """
                CREATE TABLE composerHeaders (composerId TEXT PRIMARY KEY, workspaceId TEXT, createdAt INTEGER, lastUpdatedAt INTEGER,
                  isArchived INTEGER, isSubagent INTEGER, recency INTEGER, checkpointAt INTEGER, value TEXT, subagentTypeName TEXT);
                """ : ""), nil, nil, nil)
        }
        var err: UnsafeMutablePointer<CChar>?
        sqlite3_exec(db, s, nil, nil, &err)
        if let err { Issue.record(Comment(rawValue: String(cString: err))) }
    }
    private func jsonString(_ s: String) -> String {
        String(data: (try? JSONSerialization.data(withJSONObject: [s], options: [])) ?? Data(), encoding: .utf8).map { String($0.dropFirst().dropLast()) } ?? "\"\""
    }
    private func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "''") + "'" }

    /// The chat Cursor's Agents window shows, as Cursor saves it.
    func selected(_ id: String) { sql("INSERT INTO ItemTable VALUES ('cursor/glass.selectedAgent', \(q(id)));") }

    /// The cloud agents Cursor last fetched, as it keeps them: one JSON list under the account's key. Each row is a real-shaped
    /// one with the given fields over it (times are seconds ago).
    func cloud(_ rows: [[String: Any]]) {
        let list: [[String: Any]] = rows.map { r in
            var o: [String: Any] = ["name": "Fix the footer", "repoUrl": "github.com/acme/site", "branchName": "cursor/fix-footer-b1f6",
                                    "status": 2, "workflowStatus": 2, "isUnread": true, "hasPendingInteraction": false, "isArchived": false,
                                    "isKilled": false, "hasStartedVm": true, "isOwnedByDifferentTeamMember": false, "modelDetails": ["modelName": "do-not-read"]]
            for (k, v) in r where k != "ago" { o[k] = v }
            let ago = (r["ago"] as? Double) ?? (r["ago"] as? Int).map(Double.init) ?? 120
            let ms = Int64((now.timeIntervalSince1970 - ago) * 1000)
            o["createdAt"] = ms - 600_000; o["updatedAt"] = ms; o["lastMessageActivityAtMs"] = ms
            return o
        }
        let json = String(data: (try? JSONSerialization.data(withJSONObject: list)) ?? Data(), encoding: .utf8) ?? "[]"
        sql("INSERT INTO ItemTable VALUES ('cloudAgentRepository.agents.google-oauth2%7Cuser_x', \(q(json)));")
    }

    /// A window of Cursor on `folder`: its id and the workspace.json that names the folder.
    func workspace(_ id: String, folder: String) {
        let dir = user.appendingPathComponent("workspaceStorage/\(id)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? #"{"folder": "file://\#(folder)"}"#.data(using: .utf8)!.write(to: dir.appendingPathComponent("workspace.json"))
    }

    /// A chat the way Cursor stores it. `name` and `workspace` go in the database; `lines` are the transcript's.
    func chat(_ id: String, slug: String, ago: TimeInterval = 60, name: String? = "Retry failed pages", workspace: String? = nil,
              archived: Bool = false, subagent: Bool = false, updated: TimeInterval? = nil, waiting: (name: String, params: String)? = nil, lines: [String] = CursorLines.finished) {
        if withDatabase {
            // A call it waits on is the newest message's tool call, still "loading"; two finished ones come before it.
            var bubbles = "[]"
            if let waiting {
                let done = #"{"toolFormerData":{"name":"read_file_v2","status":"completed","params":"{}"}}"#
                let call = #"{"toolFormerData":{"name":"\#(waiting.name)","status":"loading","params":\#(jsonString(waiting.params))}}"#
                bubbles = #"[{"bubbleId":"b1"},{"bubbleId":"b2"},{"bubbleId":"b3"}]"#
                sql("INSERT INTO cursorDiskKV VALUES (\(q("bubbleId:\(id):b1")), \(q(done)));")
                sql("INSERT INTO cursorDiskKV VALUES (\(q("bubbleId:\(id):b2")), \(q(done)));")
                sql("INSERT INTO cursorDiskKV VALUES (\(q("bubbleId:\(id):b3")), \(q(call)));")
            }
            let blob = name.map { #"{"composerId":"\#(id)","name":"\#($0)","status":"completed","blobEncryptionKey":"do-not-read","fullConversationHeadersOnly":\#(bubbles)\#(headers ? "" : #","workspaceIdentifier":{"id":"\#(workspace ?? "")"}"#)}"# } ?? #"{"composerId":"\#(id)"}"#
            sql("INSERT INTO cursorDiskKV VALUES (\(q("composerData:" + id)), \(q(blob)));")
            if headers {
                let stamp = updated.map { #","lastUpdatedAt":\#(Int64((now.timeIntervalSince1970 - $0) * 1000))"# } ?? ""
                let head = #"{"type":"head","composerId":"\#(id)","hasBlockingPendingActions":\#(waiting != nil)\#(stamp)}"#
            sql("INSERT INTO composerHeaders (composerId, workspaceId, isArchived, isSubagent, value) VALUES (\(q(id)), \(workspace.map(q) ?? "NULL"), \(archived ? 1 : 0), \(subagent ? 1 : 0), \(q(head)));") }
        }
        let u = url.appendingPathComponent(".cursor/projects/\(slug)/agent-transcripts/\(id)/\(id).jsonl")
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? (lines.joined(separator: "\n") + "\n").data(using: .utf8)!.write(to: u)
        try? FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-ago)], ofItemAtPath: u.path)
    }
}

private enum CursorLines {
    static func user(_ t: String) -> String {
        let text = "<timestamp>Saturday, Jul 25, 2026, 12:25 AM (UTC+3)</timestamp>\\n<user_query>\\n\(t)\\n</user_query>"
        return #"{"role":"user","message":{"content":[{"type":"text","text":"\#(text)"}]}}"#
    }
    static func said(_ t: String) -> String { #"{"role":"assistant","message":{"content":[{"type":"text","text":"\#(t)\n\n[REDACTED]"}]}}"# }
    static let tool = #"{"role":"assistant","message":{"content":[{"type":"tool_use","name":"Shell","input":{"command":"bun test"}},{"type":"tool_use","name":"StrReplace","input":{"path":"/code/scraper/retry.ts"}}]}}"#
    static let ended = #"{"type":"turn_ended","status":"success"}"#
    static let prompt = "make failed pages retry three times with backoff"
    static let reply = "Failed pages now retry three times with backoff, and the log lists the ones that never loaded."
    static let finished = [user(prompt), tool, said(reply), ended]
    static let working = [user(prompt), said("Running the tests before I touch the scheduler."), tool]
    static let aborted = [user(prompt), tool, #"{"type":"turn_ended","status":"aborted"}"#]
    /// What Cursor writes when it opens a chat whose turn was left open, or when you stop it.
    static let userAborted = [user(prompt), tool, #"{"type":"turn_ended","status":"error","error":"User aborted request"}"#]
    static let failed = [user(prompt), #"{"type":"turn_ended","status":"error","error":"Rate limit reached"}"#]
    /// A command the agent called and nothing followed: it runs, or waits for your OK.
    static let shell = [user(prompt), #"{"role":"assistant","message":{"content":[{"type":"text","text":"Running it."},{"type":"tool_use","name":"Shell","input":{"command":"rm -rf dist","description":"Remove dist"}}]}}"#]
}

@Suite struct CursorScanTests {
    @Test func aChatIsListedByItsTitleInItsFolder() {
        let h = CursorHome(), site = h.folder("code/scraper")
        h.workspace("w1", folder: site)
        h.chat("c1", slug: "code-scraper", workspace: "w1")
        let found = h.scanner.cursor(limit: 15, now: h.now)
        #expect(found.map(\.project.sessionId) == ["c1"])
        let p = found.first?.project
        #expect(p?.app == "cursor"); #expect(p?.terminal == false); #expect(p?.cwd == site)
        #expect(p?.topic == "Retry failed pages"); #expect(p?.name == "scraper")
        #expect(p?.status.text == "Cursor replied")
        #expect(p?.context == CursorLines.reply)
        #expect(p?.asked == CursorLines.prompt)   // the <user_query> wrapper and the timestamp are gone
        #expect(p?.steps.first?.text == "Opened the Cursor app")
    }

    @Test func aChatWithoutATitleGoesByYourPrompt() {
        let h = CursorHome(), site = h.folder("code/scraper")
        h.workspace("w1", folder: site)
        h.chat("c1", slug: "code-scraper", name: nil, workspace: "w1")
        #expect(h.scanner.cursor(limit: 15, now: h.now).first?.project.topic == CursorLines.prompt)
    }

    @Test func archivedAndSubagentChatsAndGoneFoldersAreLeftOut() {
        let h = CursorHome(), site = h.folder("code/scraper")
        h.workspace("w1", folder: site); h.workspace("w2", folder: h.url.path + "/code/deleted")
        h.chat("keep", slug: "code-scraper", ago: 60, workspace: "w1")
        h.chat("old", slug: "code-scraper", ago: 30, workspace: "w1", archived: true)
        h.chat("sub", slug: "code-scraper", ago: 20, workspace: "w1", subagent: true)
        h.chat("gone", slug: "code-deleted", ago: 10, workspace: "w2")
        h.chat("stale", slug: "code-scraper", ago: 20 * 86_400, workspace: "w1")
        h.chat("blank", slug: "code-scraper", ago: 5, workspace: "w1", lines: [])
        #expect(h.scanner.cursor(limit: 15, now: h.now).map(\.project.sessionId) == ["keep"])
    }

    @Test func statusFollowsTheTurn() {
        let h = CursorHome(), site = h.folder("code/scraper")
        h.workspace("w1", folder: site)
        h.chat("work", slug: "code-scraper", ago: 2, workspace: "w1", lines: CursorLines.working)
        h.chat("stop", slug: "code-scraper", ago: 60, workspace: "w1", lines: CursorLines.aborted)
        h.chat("done", slug: "code-scraper", ago: 120, workspace: "w1")
        let by = Dictionary(uniqueKeysWithValues: h.scanner.cursor(limit: 15, now: h.now).map { ($0.project.sessionId ?? "", $0.project) })
        #expect(by["work"]?.status.kind == "running"); #expect(by["work"]?.now == "Editing retry.ts")
        #expect(by["work"]?.context == "Running the tests before I touch the scheduler.")
        #expect(by["stop"]?.status.text == "You stopped Cursor")
        #expect(by["done"]?.status.kind == "done")
        // the file's age is when it last moved
        #expect(by["done"]?.lastActive.map { abs($0.timeIntervalSince(h.now.addingTimeInterval(-120))) < 1 } == true)
    }

    @Test func aTurnCursorClosedAsAbortedIsOneYouStoppedNotAnError() {
        let h = CursorHome(), site = h.folder("code/scraper")
        h.workspace("w1", folder: site)
        h.chat("abort", slug: "code-scraper", ago: 60, workspace: "w1", lines: CursorLines.userAborted)
        h.chat("fail", slug: "code-scraper", ago: 120, workspace: "w1", lines: CursorLines.failed)
        let by = Dictionary(uniqueKeysWithValues: h.scanner.cursor(limit: 15, now: h.now).map { ($0.project.sessionId ?? "", $0.project) })
        #expect(by["abort"]?.status.text == "You stopped Cursor")
        #expect(by["fail"]?.status.text == "Cursor stopped on an error"); #expect(by["fail"]?.context == "Rate limit reached")
    }

    @Test func aCallNothingFollowsRunsAndThenWaitsOnYou() {
        let h = CursorHome(), site = h.folder("code/scraper")
        h.workspace("w1", folder: site)
        h.chat("run", slug: "code-scraper", ago: 20, workspace: "w1", lines: CursorLines.shell)
        h.chat("wait", slug: "code-scraper", ago: 300, workspace: "w1", lines: CursorLines.shell)
        let by = Dictionary(uniqueKeysWithValues: h.scanner.cursor(limit: 15, now: h.now).map { ($0.project.sessionId ?? "", $0.project) })
        #expect(by["run"]?.status.kind == "running"); #expect(by["run"]?.now == "Removing dist")
        #expect(by["wait"]?.status.text == "Cursor is waiting for your OK")
    }

    @Test func whatCursorWaitsOnYouForIsARequestYouCanAnswer() {
        let h = CursorHome(), site = h.folder("code/scraper")
        h.workspace("w1", folder: site)
        h.chat("cmd", slug: "code-scraper", ago: 5, workspace: "w1", waiting: ("run_terminal_command_v2", #"{"command":"rm -rf dist","cwd":""}"#), lines: CursorLines.working)
        h.chat("web", slug: "code-scraper", ago: 6, workspace: "w1", waiting: ("web_search", #"{"searchTerm":"cursor auto-run"}"#), lines: CursorLines.working)
        h.chat("old", slug: "code-scraper", ago: 6 * 3600, workspace: "w1", waiting: ("run_terminal_command_v2", #"{"command":"ls"}"#), lines: CursorLines.working)
        let by = Dictionary(uniqueKeysWithValues: h.scanner.cursor(limit: 15, now: h.now).map { ($0.project.sessionId ?? "", $0.project) })
        #expect(by["cmd"]?.status.text == "Cursor is waiting for your OK"); #expect(by["cmd"]?.status.kind == "attention")
        #expect(by["cmd"]?.ask?.title == "Cursor wants to run a command")
        #expect(by["cmd"]?.ask?.subject == "rm -rf dist"); #expect(by["cmd"]?.ask?.answerable == true); #expect(by["cmd"]?.ask?.agent == "cursor")
        #expect(by["web"]?.ask?.title == "Cursor wants to search the web"); #expect(by["web"]?.ask?.subject == "“cursor auto-run”")
        // A chat left that way for hours is not waiting on you any more.
        #expect(by["old"]?.ask == nil)
    }

    @Test func aChatWaitingSinceYouSentYourPromptIsNotOldBecauseItsFileIs() {
        let h = CursorHome(), site = h.folder("code/scraper")
        h.workspace("w1", folder: site)
        // The transcript was last written an hour ago; the call waiting on you wrote nothing, and Cursor says the chat moved 20 s ago.
        h.chat("wait", slug: "code-scraper", ago: 3600, workspace: "w1", updated: 20, waiting: ("web_search", #"{"searchTerm":"x"}"#), lines: CursorLines.working)
        let p = h.scanner.cursor(limit: 15, now: h.now).first?.project
        #expect(p?.ask?.title == "Cursor wants to search the web")
        #expect(p.map { abs(($0.lastActive ?? .distantPast).timeIntervalSince(h.now.addingTimeInterval(-20))) < 1 } == true)
    }

    @Test func aChatThatIsNotWaitingAsksNothing() {
        let h = CursorHome(), site = h.folder("code/scraper")
        h.workspace("w1", folder: site)
        h.chat("run", slug: "code-scraper", ago: 20, workspace: "w1", lines: CursorLines.shell)
        #expect(h.scanner.cursor(limit: 15, now: h.now).first?.project.ask == nil)
    }

    @Test func aChatWithNoFolderIsNamedByItsTitle() {
        let h = CursorHome()
        h.folder(".cursor/projects/empty-window")
        h.chat("c1", slug: "empty-window", name: "How to check Codex usage", workspace: "empty-window")
        let p = h.scanner.cursor(limit: 15, now: h.now).first?.project
        #expect(p?.name == "How to check Codex usage")
    }

    @Test func theFolderComesFromTheTranscriptsFolderNameWhenTheDatabaseIsMissing() {
        let h = CursorHome(database: false), site = h.folder("code/my app/scraper")
        h.chat("c1", slug: CursorHome.slug(site))
        let p = h.scanner.cursor(limit: 15, now: h.now).first?.project
        #expect(p?.cwd == site)
        #expect(p?.topic == CursorLines.prompt)   // no title without the database
    }

    @Test func aCursorWithoutTheHeadersTableStillListsItsChats() {
        let h = CursorHome(headers: false), site = h.folder("code/scraper")
        h.workspace("w1", folder: site)
        h.chat("c1", slug: "code-scraper", workspace: "w1")
        let p = h.scanner.cursor(limit: 15, now: h.now).first?.project
        #expect(p?.cwd == site)   // from the chat's own workspace id
        #expect(p?.topic == "Retry failed pages")
        #expect(p?.status.text == "Cursor replied")
    }

    @Test func cursorSaysWhichChatItsWindowShowsByIdSoATitleSharedByTwoDoesNotConfuseThem() throws {
        let h = CursorHome()
        h.chat("a", slug: "empty-window", name: "Same title"); h.chat("b", slug: "empty-window", name: "Same title")
        h.selected("b")
        let store = try #require(CursorStore(user: h.user))
        #expect(store.selectedChat() == "b")
        h.selected("a")
        #expect(try #require(CursorStore(user: h.user)).selectedChat() == "a")
    }

    @Test func noSelectedChatIsNilNotACrash() throws {
        let h = CursorHome()
        h.chat("a", slug: "empty-window")
        #expect(try #require(CursorStore(user: h.user)).selectedChat() == nil)
    }

    @Test func cloudAgentsComeFromTheListCursorLastFetched() {
        let h = CursorHome()
        h.cloud([["bcId": "bc-done", "prUrl": "https://github.com/acme/site/pull/7"]])
        let found = h.scanner.cursor(limit: 15, now: h.now)
        #expect(found.map(\.project.sessionId) == ["bc-done"])
        let p = found.first?.project
        #expect(p?.app == "cursor"); #expect(p?.name == "site"); #expect(p?.topic == "Fix the footer"); #expect(p?.branch == "cursor/fix-footer-b1f6")
        #expect(p?.cwd == nil); #expect(p?.terminal == false); #expect(p?.status.text == "Cursor finished")
        #expect(p?.focusedAt == nil)   // unread: news
    }

    @Test func cloudAgentsShowCursorsOwnState() {
        let h = CursorHome()
        h.cloud([["bcId": "run", "workflowStatus": 1, "status": 1, "ago": 10], ["bcId": "ask", "hasPendingInteraction": true, "ago": 20],
                 ["bcId": "seen", "isUnread": false, "ago": 30], ["bcId": "old", "workflowStatus": 0, "status": 4, "ago": 40],
                 ["bcId": "boom", "workflowStatus": 3, "status": 3, "ago": 50]])
        let by = Dictionary(uniqueKeysWithValues: h.scanner.cursor(limit: 15, now: h.now).map { ($0.project.sessionId ?? "", $0.project) })
        #expect(by["run"]?.status.kind == "running"); #expect(by["run"]?.status.text == "Cursor is working")
        #expect(by["ask"]?.status.kind == "attention"); #expect(by["ask"]?.headline == "Answer it in Cursor")
        #expect(by["seen"]?.status.kind == "done"); #expect(by["seen"]?.focusedAt != nil)
        #expect(by["old"]?.status.kind == "running")   // the older status field alone: creating
        #expect(by["boom"]?.status.text == "Cursor stopped on an error")
    }

    @Test func cloudAgentsThatAreGoneOrNotYoursAreLeftOut() {
        let h = CursorHome()
        h.cloud([["bcId": "archived", "isArchived": true], ["bcId": "killed", "isKilled": true], ["bcId": "theirs", "isOwnedByDifferentTeamMember": true],
                 ["bcId": "expired", "workflowStatus": 5, "status": 5], ["bcId": "never", "workflowStatus": 3, "status": 3, "hasStartedVm": false], ["bcId": "queued", "workflowStatus": 6, "status": 4, "hasStartedVm": false],
                 ["bcId": "stale", "ago": 90 * 86_400], ["bcId": "keep"]])
        #expect(h.scanner.cursor(limit: 15, now: h.now).map(\.project.sessionId) == ["keep"])
    }

    @Test func aStartedAgentStillQueuedForBackgroundWorkReadsAsRunning() {
        let h = CursorHome()
        h.cloud([["bcId": "bg", "workflowStatus": 6, "status": 1, "hasStartedVm": true]])
        #expect(h.scanner.cursor(limit: 15, now: h.now).first?.project.status.kind == "running")
    }

    @Test func cloudAgentsShareTheLimitWithLocalChats() {
        let h = CursorHome(), site = h.folder("code/scraper")
        h.workspace("w1", folder: site)
        h.chat("c1", slug: "code-scraper", ago: 10, workspace: "w1")
        h.cloud([["bcId": "bc-1", "ago": 20], ["bcId": "bc-2", "ago": 30], ["bcId": "bc-3", "ago": 40]])
        #expect(h.scanner.cursor(limit: 2, now: h.now).count == 2)
        #expect(h.scanner.cursor(limit: 1, now: h.now).map(\.project.sessionId) == ["c1"])
    }

    @Test func cloudAgentsAreListedBesideLocalChatsAndWithoutAnyTranscript() {
        let h = CursorHome(), site = h.folder("code/scraper")
        h.workspace("w1", folder: site)
        h.chat("c1", slug: "code-scraper", workspace: "w1")
        h.cloud([["bcId": "bc-1"]])
        #expect(Set(h.scanner.cursor(limit: 15, now: h.now).compactMap(\.project.sessionId)) == ["c1", "bc-1"])
    }

    @Test func noCursorFilesMeanNoCursorChats() {
        #expect(CursorHome().scanner.cursor(limit: 15).isEmpty)
    }

    @Test func slugsAreMatchedAgainstRealFolders() {
        let h = CursorHome()
        let site = h.folder("Desktop/corgi/token/.claude/worktrees/tok-394")
        #expect(CursorApp.folder(forSlug: CursorHome.slug(site)) == site)
        #expect(CursorApp.folder(forSlug: "no-such-folder-here") == nil)
    }
}
