import Testing
import Foundation
import SQLite3
@testable import PerchCore

/// A home folder with an OpenCode database and pi session files in it, in the formats those agents write.
/// OpenCode 1 and 2 share the database: 1 writes session, message and part; 2 writes session_v2 and session_message.
private final class AgentHome {
    let url: URL
    let now = Date()
    private var db: OpaquePointer?
    init() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("perch-agents-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { sqlite3_close(db); try? FileManager.default.removeItem(at: url) }

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

    // MARK: OpenCode
    func sql(_ s: String) {
        if db == nil {
            let dir = url.appendingPathComponent(".local/share/opencode")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            sqlite3_open(dir.appendingPathComponent("opencode.db").path, &db)
            sql("""
                CREATE TABLE session (id TEXT PRIMARY KEY, project_id TEXT, parent_id TEXT, slug TEXT, directory TEXT, title TEXT, version TEXT,
                  time_created INTEGER, time_updated INTEGER, time_archived INTEGER);
                CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT, time_created INTEGER, time_updated INTEGER, data TEXT);
                CREATE TABLE part (id TEXT PRIMARY KEY, message_id TEXT, session_id TEXT, time_created INTEGER, time_updated INTEGER, data TEXT);
                CREATE TABLE session_v2 (id TEXT PRIMARY KEY, project_id TEXT, parent_id TEXT, slug TEXT, directory TEXT, title TEXT, version TEXT,
                  time_created INTEGER, time_updated INTEGER, time_archived INTEGER);
                CREATE TABLE session_message (id TEXT PRIMARY KEY, session_id TEXT, type TEXT, seq INTEGER, time_created INTEGER, time_updated INTEGER, data TEXT);
                """)
        }
        var err: UnsafeMutablePointer<CChar>?
        sqlite3_exec(db, s, nil, nil, &err)
        if let err { Issue.record(Comment(rawValue: String(cString: err))) }
    }
    private func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "''") + "'" }
    private var n = 0

    /// An OpenCode session: your prompt, then the agent's steps. `steps` are (assistant message JSON, its parts' JSON).
    func opencode(_ id: String, cwd: String, title: String = "Retry failed pages", ago: TimeInterval = 60, parent: String? = nil,
                  archived: Bool = false, prompt: String? = "make failed pages retry three times with backoff",
                  steps: [(String, [String])] = OpenCodeSteps.finished) {
        let t = Int64((now.timeIntervalSince1970 - ago) * 1000)
        sql("INSERT INTO session VALUES (\(q(id)), 'p', \(parent.map(q) ?? "NULL"), 'slug', \(q(cwd)), \(q(title)), '1.18.35', \(t - 5000), \(t), \(archived ? String(t) : "NULL"));")
        func message(_ data: String, _ parts: [String], at: Int64) {
            n += 1; let mid = "msg_\(n)"
            sql("INSERT INTO message VALUES (\(q(mid)), \(q(id)), \(at), \(at), \(q(data)));")
            for (k, p) in parts.enumerated() { sql("INSERT INTO part VALUES (\(q("prt_\(n)_\(k)")), \(q(mid)), \(q(id)), \(at), \(at), \(q(p)));") }
        }
        guard let prompt else { return }
        message(#"{"role":"user","time":{"created":\#(t - 4000)}}"#, [#"{"type":"text","text":"\#(prompt)"}"#], at: t - 4000)
        for (k, s) in steps.enumerated() { message(s.0, s.1, at: t - 3000 + Int64(k)) }
    }

    /// An OpenCode 2 session: your prompt, then its messages. `steps` are (type, message JSON); a turn ends in an idle message.
    func opencode2(_ id: String, cwd: String, title: String? = "Retry failed pages", ago: TimeInterval = 60, parent: String? = nil,
                   archived: Bool = false, prompt: String = "make failed pages retry three times with backoff",
                   steps: [(String, String)] = OpenCode2Steps.finished) {
        let t = Int64((now.timeIntervalSince1970 - ago) * 1000)
        sql("INSERT INTO session_v2 VALUES (\(q(id)), 'p', \(parent.map(q) ?? "NULL"), 'slug', \(q(cwd)), \(title.map(q) ?? "NULL"), '2.0.32', \(t - 5000), \(t), \(archived ? String(t) : "NULL"));")
        for (k, m) in ([("user", #"{"time":{"created":\#(t - 4000)},"text":"\#(prompt)"}"#)] + steps).enumerated() {
            n += 1; let at = t - 4000 + Int64(k)
            sql("INSERT INTO session_message VALUES (\(q("msg_\(n)")), \(q(id)), \(q(m.0)), \(k), \(at), \(at), \(q(m.1)));")
        }
    }

    // MARK: pi
    /// A pi session file. `entries` follow the header line.
    func pi(_ id: String, cwd: String, ago: TimeInterval = 60, entries: [String]) {
        let dir = ".pi/agent/sessions/--" + cwd.dropFirst().replacingOccurrences(of: "/", with: "-") + "--"
        let lines = [#"{"type":"session","version":3,"id":"\#(id)","timestamp":"\#(ts(-ago - 30))","cwd":"\#(cwd)"}"#] + entries
        let u = url.appendingPathComponent(dir).appendingPathComponent("2026-10-10T15-21-08-429Z_\(id).jsonl")
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? (lines.joined(separator: "\n") + "\n").data(using: .utf8)!.write(to: u)
        try? FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-ago)], ofItemAtPath: u.path)
    }
    func ts(_ offset: TimeInterval) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: now.addingTimeInterval(offset))
    }
}

enum OpenCodeSteps {
    static let toolStep = (#"{"role":"assistant","time":{"created":1,"completed":2},"finish":"tool-calls"}"#,
                           [#"{"type":"tool","tool":"bash","callID":"c1","state":{"status":"completed","input":{"command":"bun test"}}}"#])
    static let finished = [toolStep,
        (#"{"role":"assistant","time":{"created":3,"completed":4},"finish":"stop"}"#,
         [#"{"type":"text","text":"Failed pages now retry three times with backoff, and the log lists the ones that never loaded."}"#])]
    static let working = [toolStep,
        (#"{"role":"assistant","time":{"created":3}}"#,
         [#"{"type":"text","text":"Running the tests before I touch the scheduler."}"#,
          #"{"type":"tool","tool":"bash","callID":"c2","state":{"status":"running","input":{"command":"bun test --watch=false"}}}"#])]
    static let aborted = [toolStep,
        (#"{"role":"assistant","time":{"created":3,"completed":4},"error":{"name":"MessageAbortedError","data":{"message":"Aborted"}}}"#, [String]())]
    static let failed = [(#"{"role":"assistant","time":{"created":3,"completed":4},"error":{"name":"APIError","data":{"message":"Rate limit reached for this model"}}}"#, [String]())]
    static let asking = [(#"{"role":"assistant","time":{"created":3}}"#,
         [#"{"type":"tool","tool":"question","callID":"q1","state":{"status":"running","input":{"questions":[{"question":"Retry forever or give up after three?","header":"Retries","options":[{"label":"Three"},{"label":"Forever"}]}]}}}"#])]
}

/// OpenCode 2's messages: a message keeps its parts in `content`, a tool is `name`d, and the turn ends in an idle message.
enum OpenCode2Steps {
    static let toolStep = ("assistant", #"{"time":{"created":1,"completed":2},"finish":"tool-calls","content":[{"type":"tool","id":"c1","name":"shell","state":{"status":"completed","input":{"command":"bun test"}}}]}"#)
    static let finished = [toolStep,
        ("assistant", #"{"time":{"created":3,"completed":4},"finish":"stop","content":[{"type":"reasoning","text":"Done."},{"type":"text","text":"Failed pages now retry three times with backoff, and the log lists the ones that never loaded."}]}"#),
        ("idle", #"{"time":{"created":5},"outcome":"succeeded"}"#)]
    static let working = [toolStep,
        ("assistant", #"{"time":{"created":3},"content":[{"type":"text","text":"Running the tests before I touch the scheduler."},{"type":"tool","id":"c2","name":"shell","state":{"status":"running","input":{"command":"bun test --watch=false"}}}]}"#)]
    static let interrupted = [toolStep, ("idle", #"{"time":{"created":5},"outcome":"interrupted"}"#)]
    static let failed = [("assistant", #"{"time":{"created":3,"completed":4},"content":[],"error":{"type":"provider.error","message":"Rate limit reached for this model"}}"#),
        ("idle", #"{"time":{"created":5},"outcome":"failed","error":{"type":"provider.error","message":"Rate limit reached for this model"}}"#)]
    static let asking = [("assistant", #"{"time":{"created":3},"content":[{"type":"tool","id":"q1","name":"question","state":{"status":"running","input":{"questions":[{"question":"Retry forever or give up after three?","header":"Retries","options":[{"label":"Three"},{"label":"Forever"}]}]}}}]}"#)]
}

@Suite struct OtherAgentsScanTests {
    // MARK: OpenCode
    @Test func openCodeSessionsAreListedByTitle() {
        let h = AgentHome(), site = h.folder("code/scraper")
        h.opencode("ses_a", cwd: site, title: "Retry failed pages", ago: 60)
        let found = h.scanner.opencode(limit: 15, now: h.now)
        #expect(found.map(\.project.sessionId) == ["ses_a"])
        let p = found.first?.project
        #expect(p?.app == "opencode"); #expect(p?.terminal == true); #expect(p?.topic == "Retry failed pages")
        #expect(p?.status.text == "OpenCode replied")
        #expect(p?.context == "Failed pages now retry three times with backoff, and the log lists the ones that never loaded.")
    }

    @Test func openCodeSessionsThatAreNotYoursOrNotThereAreLeftOut() {
        let h = AgentHome(), site = h.folder("code/scraper")
        h.opencode("ses_a", cwd: site, ago: 60)
        h.opencode("ses_sub", cwd: site, ago: 30, parent: "ses_a")       // a subagent's
        h.opencode("ses_old", cwd: site, ago: 20, archived: true)        // archived
        h.opencode("ses_empty", cwd: site, ago: 10, prompt: nil)          // opened, never written in
        h.opencode("ses_gone", cwd: h.url.path + "/code/deleted", ago: 5) // its folder is gone
        h.opencode("ses_stale", cwd: site, ago: 20 * 86_400)             // older than two weeks
        #expect(h.scanner.opencode(limit: 15, now: h.now).map(\.project.sessionId) == ["ses_a"])
    }

    @Test func aPlaceholderTitleGivesWayToYourPrompt() {
        let h = AgentHome(), site = h.folder("code/scraper")
        h.opencode("ses_a", cwd: site, title: "New session - 2026-10-10T15:23:32.978Z")
        #expect(h.scanner.opencode(limit: 15, now: h.now).first?.project.topic == "make failed pages retry three times with backoff")
    }

    @Test func openCodeStatusFollowsItsMessages() {
        let h = AgentHome(), site = h.folder("code/scraper")
        h.opencode("work", cwd: site, ago: 2, steps: OpenCodeSteps.working)
        h.opencode("stop", cwd: site, ago: 60, steps: OpenCodeSteps.aborted)
        h.opencode("fail", cwd: site, ago: 120, steps: OpenCodeSteps.failed)
        h.opencode("ask", cwd: site, ago: 180, steps: OpenCodeSteps.asking)
        let by = Dictionary(uniqueKeysWithValues: h.scanner.opencode(limit: 15, now: h.now).map { ($0.project.sessionId ?? "", $0.project) })
        #expect(by["work"]?.status.kind == "running"); #expect(by["work"]?.now == "Running `bun test --watch=false`")
        #expect(by["work"]?.context == "Running the tests before I touch the scheduler.")
        #expect(by["stop"]?.status.text == "You stopped OpenCode"); #expect(by["stop"]?.stoppedAt != nil)
        #expect(by["fail"]?.status.text == "OpenCode stopped on an error"); #expect(by["fail"]?.context == "Rate limit reached for this model")
        #expect(by["ask"]?.status.text == "OpenCode asked you something")
    }

    @Test func openCode2SessionsAreListedByTitle() {
        let h = AgentHome(), site = h.folder("code/scraper")
        h.opencode2("ses_a", cwd: site, title: "Retry failed pages", ago: 60)
        let found = h.scanner.opencode(limit: 15, now: h.now)
        #expect(found.map(\.project.sessionId) == ["ses_a"])
        let p = found.first?.project
        #expect(p?.app == "opencode"); #expect(p?.terminal == true); #expect(p?.topic == "Retry failed pages")
        #expect(p?.status.text == "OpenCode replied")
        #expect(p?.context == "Failed pages now retry three times with backoff, and the log lists the ones that never loaded.")
    }

    @Test func openCode2SessionsThatAreNotYoursAreLeftOutAndAnUntitledOneTakesYourPrompt() {
        let h = AgentHome(), site = h.folder("code/scraper")
        h.opencode2("ses_a", cwd: site, title: nil, ago: 60)
        h.opencode2("ses_sub", cwd: site, ago: 30, parent: "ses_a")
        h.opencode2("ses_old", cwd: site, ago: 20, archived: true)
        let found = h.scanner.opencode(limit: 15, now: h.now)
        #expect(found.map(\.project.sessionId) == ["ses_a"])
        #expect(found.first?.project.topic == "make failed pages retry three times with backoff")
    }

    @Test func openCode2StatusFollowsItsMessages() {
        let h = AgentHome(), site = h.folder("code/scraper")
        h.opencode2("work", cwd: site, ago: 2, steps: OpenCode2Steps.working)
        h.opencode2("stop", cwd: site, ago: 60, steps: OpenCode2Steps.interrupted)
        h.opencode2("fail", cwd: site, ago: 120, steps: OpenCode2Steps.failed)
        h.opencode2("ask", cwd: site, ago: 180, steps: OpenCode2Steps.asking)
        let by = Dictionary(uniqueKeysWithValues: h.scanner.opencode(limit: 15, now: h.now).map { ($0.project.sessionId ?? "", $0.project) })
        #expect(by["work"]?.status.kind == "running"); #expect(by["work"]?.now == "Running `bun test --watch=false`")
        #expect(by["work"]?.context == "Running the tests before I touch the scheduler.")
        #expect(by["stop"]?.status.text == "You stopped OpenCode"); #expect(by["stop"]?.stoppedAt != nil)
        #expect(by["fail"]?.status.text == "OpenCode stopped on an error"); #expect(by["fail"]?.context == "Rate limit reached for this model")
        #expect(by["ask"]?.status.text == "OpenCode asked you something")
    }

    /// OpenCode 2 keeps a step's tool calls inside its message: the pull request a command opened is found there too.
    @Test func aPullRequestOpenCode2OpenedIsFound() {
        let h = AgentHome(), site = h.folder("code/scraper")
        let call = #"{"type":"tool","id":"call_pr","name":"shell","state":{"status":"completed","input":{"command":"\#(PullRequestScan.create) --fill"},"content":[{"type":"text","text":"https://github.com/acme/scraper/pull/42\n"}]}}"#
        h.opencode2("ses_a", cwd: site, steps: [("assistant", #"{"time":{"created":1,"completed":2},"finish":"tool-calls","content":[\#(call)]}"#)] + OpenCode2Steps.finished)
        #expect(h.scanner.opencode(limit: 15, now: h.now).first?.project.prs.map(\.url) == ["https://github.com/acme/scraper/pull/42"])
    }

    /// A file read whose output shows the command and an address is not a pull request the session opened.
    @Test func aPullRequestOpenCodeOnlyReadAboutIsNotFound() {
        let h = AgentHome(), site = h.folder("code/scraper")
        let shown = PullRequestScan.create + " --fill\\nhttps://github.com/acme/scraper/pull/42\\n"
        let read2 = #"{"type":"tool","id":"call_read","name":"read","state":{"status":"completed","input":{"path":"notes.md"},"content":[{"type":"text","text":"\#(shown)"}]}}"#
        h.opencode2("ses_a", cwd: site, steps: [("assistant", #"{"time":{"created":1,"completed":2},"finish":"tool-calls","content":[\#(read2)]}"#)] + OpenCode2Steps.finished)
        let read1 = #"{"type":"tool","tool":"read","callID":"c_read","state":{"status":"completed","input":{"filePath":"notes.md"},"output":"\#(shown)"}}"#
        h.opencode("ses_b", cwd: site, steps: [(#"{"role":"assistant","time":{"created":1,"completed":2},"finish":"tool-calls"}"#, [read1])] + OpenCodeSteps.finished)
        #expect(h.scanner.opencode(limit: 15, now: h.now).allSatisfy { $0.project.prs.isEmpty })
    }

    /// A session counts as changed when any of its messages did, even if its own row is older.
    @Test func anOpenCodeSessionWithANewerMessageThanItsRowIsListed() {
        let h = AgentHome(), site = h.folder("code/scraper")
        h.opencode2("ses_old_row", cwd: site, ago: 3 * 86_400)
        h.opencode("ses_old_row_1", cwd: site, ago: 3 * 86_400)
        let recent = Int64((h.now.timeIntervalSince1970 - 60) * 1000)
        h.sql("UPDATE session_message SET time_updated = \(recent) WHERE session_id = 'ses_old_row'; UPDATE message SET time_updated = \(recent) WHERE session_id = 'ses_old_row_1';")
        let store = OpenCodeStore(url: h.url.appendingPathComponent(".local/share/opencode/opencode.db"))
        let found = store?.sessions(after: h.now.addingTimeInterval(-86_400), limit: 15) ?? []
        #expect(Set(found.map(\.id)) == ["ses_old_row", "ses_old_row_1"])
        #expect(found.allSatisfy { abs($0.updated.timeIntervalSince(h.now.addingTimeInterval(-60))) < 1 })
    }

    /// OpenCode 2 copies OpenCode 1's sessions into its own tables when it first runs; one written by OpenCode 1 since is still read.
    @Test func aDatabaseBothVersionsWroteListsEachSessionOnce() {
        let h = AgentHome(), site = h.folder("code/scraper")
        h.opencode("ses_copied", cwd: site, title: "Before the update", ago: 300)
        h.opencode2("ses_copied", cwd: site, title: "After the update", ago: 30)
        h.opencode("ses_one", cwd: site, title: "Only in OpenCode 1", ago: 60)
        let found = h.scanner.opencode(limit: 15, now: h.now)
        #expect(found.map(\.project.sessionId) == ["ses_copied", "ses_one"])
        #expect(found.map(\.project.topic) == ["After the update", "Only in OpenCode 1"])
    }

    @Test func noOpenCodeDatabaseMeansNoOpenCodeSessions() {
        #expect(AgentHome().scanner.opencode(limit: 15).isEmpty)
    }

    // MARK: pi
    static func user(_ t: String, _ at: String) -> String { #"{"type":"message","id":"u","parentId":null,"timestamp":"\#(at)","message":{"role":"user","content":[{"type":"text","text":"\#(t)"}],"timestamp":1}}"# }
    static func assistant(_ blocks: String, stop: String, _ at: String, extra: String = "") -> String {
        #"{"type":"message","id":"a","parentId":"u","timestamp":"\#(at)","message":{"role":"assistant","content":[\#(blocks)],"api":"x","provider":"x","model":"x","stopReason":"\#(stop)"\#(extra),"timestamp":1}}"#
    }
    static let toolCall = #"{"type":"toolCall","id":"c1","name":"bash","arguments":{"command":"npm test"}}"#
    static let result = #"{"type":"message","id":"r","parentId":"a","timestamp":"2026-10-10T15:21:19Z","message":{"role":"toolResult","toolCallId":"c1","toolName":"bash","content":[{"type":"text","text":"ok"}],"isError":false,"timestamp":1}}"#
    static func said(_ t: String) -> String { #"{"type":"text","text":"\#(t)"}"# }

    @Test func piSessionsAreListedByNameOrFirstPrompt() {
        let h = AgentHome(), site = h.folder("code/scraper")
        h.pi("p1", cwd: site, ago: 60, entries: [
            Self.user("make failed pages retry three times with backoff", h.ts(-90)),
            Self.assistant(Self.toolCall, stop: "toolUse", h.ts(-80)), Self.result,
            Self.assistant(Self.said("Failed pages now retry three times, waiting 1, 4 and 16 seconds."), stop: "stop", h.ts(-70)),
        ])
        h.pi("p2", cwd: site, ago: 120, entries: [
            Self.user("add a progress bar to the crawler output", h.ts(-150)),
            Self.assistant(Self.toolCall, stop: "toolUse", h.ts(-140)), Self.result,
            Self.assistant(Self.said("The crawler shows a progress bar with pages done and pages left."), stop: "stop", h.ts(-130)),
            #"{"type":"session_info","id":"i","parentId":"a","timestamp":"\#(h.ts(-125))","name":"Crawler progress bar"}"#,
        ])
        let found = h.scanner.pi(limit: 15, now: h.now).map(\.project)
        #expect(found.map(\.sessionId) == ["p1", "p2"])
        #expect(found.map(\.topic) == ["make failed pages retry three times with backoff", "Crawler progress bar"])
        #expect(found.first?.app == "pi"); #expect(found.first?.terminal == true)
        #expect(found.first?.startedAt.map { abs($0.timeIntervalSince(h.now.addingTimeInterval(-90))) < 1 } == true)   // the header's time
        #expect(found.first?.status.text == "pi replied")
        #expect(found.first?.said == "Failed pages now retry three times, waiting 1, 4 and 16 seconds.")
    }

    @Test func piStatusFollowsTheLastStop() {
        let h = AgentHome(), site = h.folder("code/scraper")
        h.pi("work", cwd: site, ago: 2, entries: [Self.user("run the full crawl please, all pages", h.ts(-10)), Self.assistant(Self.toolCall, stop: "toolUse", h.ts(-5))])
        h.pi("stop", cwd: site, ago: 60, entries: [Self.user("run the full crawl please, all pages", h.ts(-90)), Self.assistant(Self.toolCall, stop: "toolUse", h.ts(-80)), Self.result,
                                                   Self.assistant("", stop: "aborted", h.ts(-70))])
        h.pi("fail", cwd: site, ago: 120, entries: [Self.user("run the full crawl please, all pages", h.ts(-150)), Self.assistant(Self.toolCall, stop: "toolUse", h.ts(-140)), Self.result,
                                                    Self.assistant("", stop: "error", h.ts(-130), extra: #","errorMessage":"429 Too Many Requests""#)])
        let by = Dictionary(uniqueKeysWithValues: h.scanner.pi(limit: 15, now: h.now).map { ($0.project.sessionId ?? "", $0.project) })
        #expect(by["work"]?.status.kind == "running"); #expect(by["work"]?.now == "Running `npm test`")
        #expect(by["stop"]?.status.text == "You stopped pi")
        #expect(by["fail"]?.status.text == "pi stopped on an error"); #expect(by["fail"]?.context == "429 Too Many Requests")
    }

    @Test func piSessionsThatAreNotWorthARowAreLeftOut() {
        let h = AgentHome(), site = h.folder("code/scraper")
        // small talk
        h.pi("hi", cwd: site, ago: 30, entries: [Self.user("hi", h.ts(-40)), Self.assistant(Self.said("Hi! How can I help?"), stop: "stop", h.ts(-35))])
        // a folder that is gone
        h.pi("gone", cwd: h.url.path + "/code/deleted", ago: 20, entries: [Self.user("make failed pages retry three times", h.ts(-30)),
                                                                           Self.assistant(Self.toolCall, stop: "toolUse", h.ts(-25)), Self.result])
        // opened and closed without a word
        h.pi("empty", cwd: site, ago: 10, entries: [])
        // Only the small talk is found, marked: the app lists it only while pi still runs it.
        let found = h.scanner.pi(limit: 15, now: h.now).map(\.project)
        #expect(found.map(\.sessionId) == ["hi"]); #expect(found.first?.smallTalk == true)
    }
}
