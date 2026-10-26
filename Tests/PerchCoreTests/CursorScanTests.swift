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
    init(database: Bool = true) {
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
                CREATE TABLE composerHeaders (composerId TEXT PRIMARY KEY, workspaceId TEXT, createdAt INTEGER, lastUpdatedAt INTEGER,
                  isArchived INTEGER, isSubagent INTEGER, recency INTEGER, checkpointAt INTEGER, value TEXT, subagentTypeName TEXT);
                """, nil, nil, nil)
        }
        var err: UnsafeMutablePointer<CChar>?
        sqlite3_exec(db, s, nil, nil, &err)
        if let err { Issue.record(Comment(rawValue: String(cString: err))) }
    }
    private func jsonString(_ s: String) -> String {
        String(data: (try? JSONSerialization.data(withJSONObject: [s], options: [])) ?? Data(), encoding: .utf8).map { String($0.dropFirst().dropLast()) } ?? "\"\""
    }
    private func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "''") + "'" }

    /// A window of Cursor on `folder`: its id and the workspace.json that names the folder.
    func workspace(_ id: String, folder: String) {
        let dir = user.appendingPathComponent("workspaceStorage/\(id)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? #"{"folder": "file://\#(folder)"}"#.data(using: .utf8)!.write(to: dir.appendingPathComponent("workspace.json"))
    }

    /// A chat the way Cursor stores it. `name` and `workspace` go in the database; `lines` are the transcript's.
    func chat(_ id: String, slug: String, ago: TimeInterval = 60, name: String? = "Retry failed pages", workspace: String? = nil,
              archived: Bool = false, subagent: Bool = false, waiting: (name: String, params: String)? = nil, lines: [String] = CursorLines.finished) {
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
            let blob = name.map { #"{"composerId":"\#(id)","name":"\#($0)","status":"completed","blobEncryptionKey":"do-not-read","fullConversationHeadersOnly":\#(bubbles)}"# } ?? #"{"composerId":"\#(id)"}"#
            sql("INSERT INTO cursorDiskKV VALUES (\(q("composerData:" + id)), \(q(blob)));")
            let head = #"{"type":"head","composerId":"\#(id)","hasBlockingPendingActions":\#(waiting != nil)}"#
            sql("INSERT INTO composerHeaders (composerId, workspaceId, isArchived, isSubagent, value) VALUES (\(q(id)), \(workspace.map(q) ?? "NULL"), \(archived ? 1 : 0), \(subagent ? 1 : 0), \(q(head)));")
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
