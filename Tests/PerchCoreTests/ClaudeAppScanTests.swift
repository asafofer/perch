import Testing
import Foundation
@testable import PerchCore

/// What V8 writes for plain data, enough to build the Claude app's persisted query cache in a test.
private enum V8 {
    static func varint(_ n: Int) -> [UInt8] { var n = n, out: [UInt8] = []; repeat { var b = UInt8(n & 0x7F); n >>= 7; if n > 0 { b |= 0x80 }; out.append(b) } while n > 0; return out }
    static func encode(_ v: Any) -> [UInt8] {
        switch v {
        case let s as String:
            if s.unicodeScalars.allSatisfy({ $0.value < 256 }) { return [UInt8(ascii: "\"")] + varint(s.unicodeScalars.count) + s.unicodeScalars.map { UInt8($0.value) } }
            let u = Array(s.utf16).flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
            return [UInt8(ascii: "c")] + varint(u.count) + u
        case let b as Bool: return [UInt8(ascii: b ? "T" : "F")]
        case let n as Int: return [UInt8(ascii: "I")] + varint(n >= 0 ? n << 1 : (~n << 1) | 1)
        case let d as Double: return [UInt8(ascii: "N")] + withUnsafeBytes(of: d.bitPattern.littleEndian, Array.init)
        case let a as [Any]: return [UInt8(ascii: "A")] + varint(a.count) + a.flatMap(encode) + [UInt8(ascii: "$")] + varint(0) + varint(a.count)
        case let o as KeyValuePairs<String, Any>:
            return [UInt8(ascii: "o")] + o.flatMap { encode($0.key) + encode($0.value) } + [UInt8(ascii: "{")] + varint(o.count)
        case is NSNull: return [UInt8(ascii: "0")]
        default: fatalError("not in the test encoder: \(v)")
        }
    }
    /// An IndexedDB value as Chromium stores a large one: Blink's and V8's headers, then Snappy (here all literals).
    static func blob(_ v: Any) -> Data {
        let raw: [UInt8] = [0xFF, 0x15, 0xFE] + [UInt8](repeating: 0, count: 12) + [0xFF, 0x0F] + encode(v)
        var out: [UInt8] = [0xFF, 0x11, 0x02] + varint(raw.count), i = 0
        while i < raw.count {
            let n = min(60, raw.count - i)
            out.append(UInt8((n - 1) << 2)); out += raw[i..<i + n]; i += n
        }
        return Data(out)
    }
}

private func chat(_ id: String, _ name: String, _ updated: String, project: Any = NSNull()) -> KeyValuePairs<String, Any> {
    ["uuid": id, "name": name, "summary": "", "updated_at": updated, "created_at": updated, "project_uuid": project, "is_starred": false]
}

/// A task as the app lists it (`cowork-remote-sessions`): times in milliseconds.
private func task(_ id: String, _ title: String, at: Date, live: String = "idle", running: Bool = false, unread: Bool = true,
                  folders: [Any] = [], archived: Bool = false) -> KeyValuePairs<String, Any> {
    ["cwd": "", "userSelectedFolders": folders, "sessionId": id, "isRunning": running, "title": title, "model": "claude-opus-5-5",
     "createdAt": at.timeIntervalSince1970 * 1000 - 60_000, "lastActivityAt": at.timeIntervalSince1970 * 1000, "isArchived": archived,
     "liveStatus": live, "rawSessionStatus": live, "isStarred": false, "unread": unread]
}

private func cache(_ chats: [Any], starred: [Any] = [], projects: [Any] = [], tasks: [Any] = []) -> KeyValuePairs<String, Any> {
    let list: KeyValuePairs<String, Any> = [
        "queryKey": ["chat_conversation_list", ["orgUuid": "org"] as KeyValuePairs<String, Any>, "infinite",
                     ["limit": 30, "starred": NSNull(), "archived": false] as KeyValuePairs<String, Any>] as [Any],
        "state": ["data": ["pages": [chats] as [Any], "pageParams": [0] as [Any]] as KeyValuePairs<String, Any>] as KeyValuePairs<String, Any>,
    ]
    let star: KeyValuePairs<String, Any> = [
        "queryKey": ["chat_conversation_list", ["orgUuid": "org"] as KeyValuePairs<String, Any>, ["starred": true] as KeyValuePairs<String, Any>] as [Any],
        "state": ["data": ["data": starred] as KeyValuePairs<String, Any>] as KeyValuePairs<String, Any>,
    ]
    let proj: KeyValuePairs<String, Any> = [
        "queryKey": ["project_list", ["orgUuid": "org"] as KeyValuePairs<String, Any>] as [Any],
        "state": ["data": projects] as KeyValuePairs<String, Any>,
    ]
    let remote: KeyValuePairs<String, Any> = [
        "queryKey": ["cowork-remote-sessions", "org", true] as [Any],
        "state": ["data": tasks] as KeyValuePairs<String, Any>,
    ]
    let local: KeyValuePairs<String, Any> = [
        "queryKey": ["cowork-local-sessions", "org"] as [Any],
        "state": ["data": ["v": 1, "accountUuid": "acct", "rows": [] as [Any]] as KeyValuePairs<String, Any>] as KeyValuePairs<String, Any>,
    ]
    return ["timestamp": 1, "buster": "conversations_v2:1", "clientState": ["mutations": [] as [Any], "queries": [list, star, proj, local, remote] as [Any]] as KeyValuePairs<String, Any>]
}


/// LevelDB's write-ahead log as Chromium leaves it: one batch per record, each record in a 32 KB block behind its header.
private func leveldbLog(_ puts: [(key: [UInt8], value: [UInt8])], seq: UInt64 = 1) -> Data {
    var batch = [UInt8](withUnsafeBytes(of: seq.littleEndian, Array.init)) + withUnsafeBytes(of: UInt32(puts.count).littleEndian, Array.init)
    for p in puts { batch += [1] + V8.varint(p.key.count) + p.key + V8.varint(p.value.count) + p.value }
    precondition(batch.count < 32_000)
    return Data([0, 0, 0, 0, UInt8(batch.count & 0xFF), UInt8(batch.count >> 8), 1] + batch)
}

/// One conversation as claude.ai caches it: a version number, Blink's and V8's headers, the object.
private func conversation(_ id: String, product: String, tree: KeyValuePairs<String, Any>, writtenAt: Int = 1) -> [UInt8] {
    let o: KeyValuePairs<String, Any> = ["conversationUuid": id, "product": product, "accountUuid": "acct", "tree": tree, "writtenAt": writtenAt]
    return [0x40, 0xFF, 0x15, 0xFE] + [UInt8](repeating: 0, count: 12) + [0xFF, 0x0F] + V8.encode(o)
}

private final class Home {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("perch-claudeapp-\(UUID().uuidString)")
    let now = Date()
    var app: URL { url.appendingPathComponent("Library/Application Support/Claude") }
    deinit { try? FileManager.default.removeItem(at: url) }
    var scanner: SessionScanner {
        let s = SessionScanner(home: url, desktop: DesktopSessions(root: url.appendingPathComponent("none")))
        s.usable = { _ in true }
        s.lookUpGit = { _ in nil }; s.lookUpBranch = { _ in nil }; s.lookUpRepo = { _ in nil }
        return s
    }
    func write(_ u: URL, _ data: Data, ago: TimeInterval = 60) {
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: u)
        try? FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-ago)], ofItemAtPath: u.path)
    }
    /// The app's cached lists, where Chromium keeps them.
    func lists(_ v: KeyValuePairs<String, Any>, ago: TimeInterval = 60) {
        write(app.appendingPathComponent("IndexedDB/https_claude.ai_0.indexeddb.blob/1/bf/bf47"), V8.blob(v), ago: ago)
    }
}

@Suite struct ClaudeAppScanTests {
    @Test func tasksComeFromTheAppsOwnListWithItsState() {
        let h = Home()
        let folder = h.url.appendingPathComponent("Documents/Taxes").path
        h.lists(cache([], tasks: [task("cse_a", "Sort the receipts", at: h.now.addingTimeInterval(-120), folders: [folder]),
                                  task("cse_b", "Find a venue", at: h.now.addingTimeInterval(-60), live: "running", running: true),
                                  task("cse_c", "Book the table", at: h.now.addingTimeInterval(-30), live: "awaiting"),
                                  task("cse_d", "Old one", at: h.now.addingTimeInterval(-10), archived: true)]))
        let found = h.scanner.tasks(limit: 10).map(\.project)
        #expect(found.map(\.sessionId) == ["cse_c", "cse_b", "cse_a"])    // newest first, the archived one left out
        #expect(found.map { $0.status.kind } == ["attention", "running", "done"])
        #expect(found[2].name == "Taxes")                    // named after your folder
        #expect(found[1].name == "")                         // no folder: its title alone
        #expect(found[2].topic == "Sort the receipts")
        #expect(found.allSatisfy { $0.app == "cowork" && $0.desktopSessionId == $0.sessionId })
    }

    @Test func aTaskYouHaveSeenInTheAppIsNotNews() {
        let h = Home(), at = h.now.addingTimeInterval(-60)
        h.lists(cache([], tasks: [task("cse_a", "Seen", at: at, unread: false), task("cse_b", "Not seen", at: at)]))
        let found = Dictionary(uniqueKeysWithValues: h.scanner.tasks(limit: 10).map { ($0.project.sessionId ?? "", $0.project) })
        #expect(abs((found["cse_a"]?.focusedAt ?? .distantPast).timeIntervalSince(at)) < 0.01)   // through milliseconds and back
        #expect(found["cse_b"]?.focusedAt == nil)
    }

    @Test func whatATaskAndAChatSaidComesFromTheAppsLevelDB() throws {
        let ts = "2026-10-21T17:10:00.000Z"
        let taskTree: KeyValuePairs<String, Any> = ["kind": "events", "events": [
            ["kind": "message", "seq": 1, "payload": ["type": "user", "timestamp": ts, "message": ["role": "user", "content": "fetch example.com and tell me its title"] as KeyValuePairs<String, Any>] as KeyValuePairs<String, Any>] as KeyValuePairs<String, Any>,
            ["kind": "message", "seq": 2, "payload": ["type": "system", "subtype": "status"] as KeyValuePairs<String, Any>] as KeyValuePairs<String, Any>,
            ["kind": "message", "seq": 3, "payload": ["type": "assistant", "timestamp": ts, "message": ["role": "assistant", "stop_reason": "end_turn",
                "content": [["type": "text", "text": "The page title is Example Domain."] as KeyValuePairs<String, Any>] as [Any]] as KeyValuePairs<String, Any>] as KeyValuePairs<String, Any>] as KeyValuePairs<String, Any>,
        ] as [Any]]
        let chatTree: KeyValuePairs<String, Any> = ["uuid": "c1", "current_leaf_message_uuid": "m2",
            "messageByUuid": ["m1": ["uuid": "m1", "sender": "human", "content": [["type": "text", "text": "Reply with one word: pong"] as KeyValuePairs<String, Any>] as [Any]] as KeyValuePairs<String, Any>,
                              "m2": ["uuid": "m2", "sender": "assistant", "created_at": ts, "content": [["type": "text", "text": "Pong."] as KeyValuePairs<String, Any>] as [Any]] as KeyValuePairs<String, Any>] as KeyValuePairs<String, Any>,
            "parentByChildUuid": ["m2": "m1"] as KeyValuePairs<String, Any>]
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("perch-ldb-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let ldb = dir.appendingPathComponent("https_claude.ai_0.indexeddb.leveldb")
        try FileManager.default.createDirectory(at: ldb, withIntermediateDirectories: true)
        try leveldbLog([(Array("k1".utf8), conversation("cowork:cse_a", product: "cowork", tree: taskTree)),
                        (Array("k2".utf8), conversation("c1", product: "chat", tree: chatTree)),
                        (Array("k3".utf8), conversation("code:cse_z", product: "code", tree: taskTree))]).write(to: ldb.appendingPathComponent("000003.log"))
        let words = ClaudeWords(idb: dir).read()
        #expect(Set(words.keys) == ["cse_a", "c1"])          // Claude Code's cloud sessions are not read
        #expect(words["cse_a"]?.lastAssistantText == "The page title is Example Domain.")
        #expect(words["c1"]?.lastAssistantText == "Pong.")
        #expect(words["c1"]?.lastUserText == "Reply with one word: pong")
        let task = Recap.task(ClaudeCache.Task(id: "cse_a", title: "Example title", folders: [], created: nil, lastActivity: Date(), state: .idle, unread: true, archived: false),
                              words: words["cse_a"], now: Date())
        #expect(task.context == "The page title is Example Domain.")
        #expect(task.headline == "")
        let bare = Recap.task(ClaudeCache.Task(id: "cse_b", title: "Elsewhere", folders: [], created: nil, lastActivity: Date(), state: .idle, unread: true, archived: false), now: Date())
        #expect(bare.headline == "Not opened on this Mac yet")
    }

    @Test func aLaterWriteOfAKeyWinsAndADeleteRemovesIt() {
        var log = [UInt8](leveldbLog([(Array("a".utf8), Array("old".utf8)), (Array("b".utf8), Array("gone".utf8))], seq: 1))
        // A second batch: a new value for a, b deleted.
        var batch = [UInt8](withUnsafeBytes(of: UInt64(10).littleEndian, Array.init)) + withUnsafeBytes(of: UInt32(2).littleEndian, Array.init)
        batch += [1] + V8.varint(1) + Array("a".utf8) + V8.varint(3) + Array("new".utf8)
        batch += [0] + V8.varint(1) + Array("b".utf8)
        log += [0, 0, 0, 0, UInt8(batch.count), 0, 1] + batch
        var got: [Data: (UInt64, Data?)] = [:]
        LevelDB.log(log) { k, seq, v in if (got[k]?.0 ?? 0) <= seq { got[k] = (seq, v) } }
        #expect(got[Data("a".utf8)]?.1 == Data("new".utf8))
        #expect(got[Data("b".utf8)]?.1 == nil)
    }

    @Test func recentChatsComeFromTheAppsCachedList() throws {
        let data = V8.blob(cache([chat("c1", "Planning a trip to Paris", "2026-10-19T12:50:19.139834Z"),
                                  chat("c2", "Quarterly numbers", "2026-10-21T15:20:13.839Z", project: "p1"),
                                  chat("c3", "Caf\u{e9} \u{05e9}\u{05dc}\u{05d5}\u{05dd}", "2026-10-18T09:00:00Z")],
                                 starred: [chat("c9", "Starred only", "2026-10-21T16:00:00Z")],
                                 projects: [["uuid": "p1", "name": "financials"] as KeyValuePairs<String, Any>]))
        let chats = try #require(ClaudeCache.contents(fromBlob: data)?.chats)
        #expect(chats.map(\.id) == ["c2", "c1", "c3"])      // newest first; the starred filter's own list is not the sidebar
        #expect(chats[0].project == "financials")
        #expect(chats[1].project == nil)
        #expect(chats[2].title == "Caf\u{e9} \u{05e9}\u{05dc}\u{05d5}\u{05dd}")
        #expect(chats[1].updated == ClaudeCache.date("2026-10-19T12:50:19.139Z"))
    }

    @Test func chatsAreFoundInTheIndexedDBBlobsAndOpenByTheirId() {
        let h = Home()
        let recent = ISO8601DateFormatter().string(from: h.now.addingTimeInterval(-3600))
        let blobs = h.app.appendingPathComponent("IndexedDB/https_claude.ai_0.indexeddb.blob/1")
        h.write(blobs.appendingPathComponent("00/0a"), Data([0xFF, 0x11, 0x02, 0x00]), ago: 10)   // another value
        h.write(blobs.appendingPathComponent("bf/bf47"), V8.blob(cache([chat("c1", "Anniversary dinner ideas", recent)])))
        let found = h.scanner.chats(limit: 10)
        #expect(found.count == 1)
        #expect(found[0].project.app == "chat")
        #expect(found[0].project.topic == "Anniversary dinner ideas")
        #expect(found[0].project.sessionId == "c1")
    }

    @Test func aDamagedCacheReadsAsNothing() {
        #expect(ClaudeCache.contents(fromBlob: Data([0xFF, 0x11, 0x02, 0x05, 0x00])) == nil)
        var data = V8.blob(cache([chat("c1", "x", "2026-10-19T12:50:19Z")]))
        data.removeLast(20)
        #expect(ClaudeCache.contents(fromBlob: data) == nil)
    }

    @Test func chatsStartSwitchedOffAndTasksOn() {
        #expect(Agent.chat.onByDefault == false)
        #expect(Agent.cowork.onByDefault)
    }
}
