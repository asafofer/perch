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

private func cache(_ chats: [Any], starred: [Any] = [], projects: [Any] = []) -> KeyValuePairs<String, Any> {
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
    return ["timestamp": 1, "buster": "conversations_v2:1", "clientState": ["mutations": [] as [Any], "queries": [list, star, proj] as [Any]] as KeyValuePairs<String, Any>]
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
    /// A Cowork task: its record, and its transcript in its own folder's `.claude/projects`.
    func cowork(_ id: String, title: String, folders: [String] = [], archived: Bool = false, ago: TimeInterval = 60) {
        let dir = app.appendingPathComponent("local-agent-mode-sessions/acct/org")
        let own = dir.appendingPathComponent("local_\(id)")
        let cwd = own.appendingPathComponent("outputs").path
        let entry: [String: Any] = ["sessionId": "local_\(id)", "cliSessionId": "cli-\(id)", "cwd": cwd, "title": title,
                                    "userSelectedFolders": folders, "isArchived": archived]
        write(dir.appendingPathComponent("local_\(id).json"), try! JSONSerialization.data(withJSONObject: entry))
        let ts = ISO8601DateFormatter().string(from: now.addingTimeInterval(-ago))
        let lines = [
            #"{"type":"user","sessionId":"cli-\#(id)","cwd":"\#(cwd)","entrypoint":"local-agent","timestamp":"\#(ts)","message":{"content":"find the venue's opening hours"}}"#,
            #"{"type":"assistant","sessionId":"cli-\#(id)","cwd":"\#(cwd)","timestamp":"\#(ts)","message":{"stop_reason":"tool_use","content":[{"type":"tool_use","id":"t1","name":"WebSearch","input":{"query":"venue hours"}}]}}"#,
            #"{"type":"user","sessionId":"cli-\#(id)","cwd":"\#(cwd)","timestamp":"\#(ts)","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]}}"#,
            #"{"type":"assistant","sessionId":"cli-\#(id)","cwd":"\#(cwd)","timestamp":"\#(ts)","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"It opens at nine on weekdays."}]}}"#,
        ]
        write(own.appendingPathComponent(".claude/projects/-outputs/cli-\(id).jsonl"), Data((lines.joined(separator: "\n") + "\n").utf8), ago: ago)
    }
}

@Suite struct ClaudeAppScanTests {
    @Test func coworkTasksAreListedByTheirTitleAndOpenInTheClaudeApp() {
        let h = Home()
        h.cowork("a", title: "Venue opening hours")
        h.cowork("b", title: "Old task", archived: true)
        let found = h.scanner.cowork(limit: 10)
        #expect(found.count == 1)
        let p = found[0].project
        #expect(p.app == "cowork")
        #expect(p.name == "Venue opening hours")          // no folder of yours: its own outputs folder says nothing
        #expect(p.desktopSessionId == "local_a")
        #expect(p.context == "It opens at nine on weekdays.")
    }

    @Test func aCoworkTaskWithYourFolderIsNamedAfterIt() {
        let h = Home()
        let folder = h.url.appendingPathComponent("Documents/Taxes").path
        h.cowork("a", title: "Sort the receipts", folders: [folder])
        let p = h.scanner.cowork(limit: 10)[0].project
        #expect(p.name == "Taxes")
        #expect(p.topic == "Sort the receipts")
    }

    @Test func recentChatsComeFromTheAppsCachedList() throws {
        let data = V8.blob(cache([chat("c1", "Planning a trip to Paris", "2026-10-19T12:50:19.139834Z"),
                                  chat("c2", "Quarterly numbers", "2026-10-21T15:20:13.839Z", project: "p1"),
                                  chat("c3", "Caf\u{e9} \u{05e9}\u{05dc}\u{05d5}\u{05dd}", "2026-10-18T09:00:00Z")],
                                 starred: [chat("c9", "Starred only", "2026-10-21T16:00:00Z")],
                                 projects: [["uuid": "p1", "name": "financials"] as KeyValuePairs<String, Any>]))
        let chats = try #require(ClaudeChats.chats(fromBlob: data))
        #expect(chats.map(\.id) == ["c2", "c1", "c3"])      // newest first; the starred filter's own list is not the sidebar
        #expect(chats[0].project == "financials")
        #expect(chats[1].project == nil)
        #expect(chats[2].title == "Caf\u{e9} \u{05e9}\u{05dc}\u{05d5}\u{05dd}")
        #expect(chats[1].updated == ClaudeChats.date("2026-10-19T12:50:19.139Z"))
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

    @Test func aDamagedCacheReadsAsNoChats() {
        #expect(ClaudeChats.chats(fromBlob: Data([0xFF, 0x11, 0x02, 0x05, 0x00])) == nil)
        var data = V8.blob(cache([chat("c1", "x", "2026-10-19T12:50:19Z")]))
        data.removeLast(20)
        #expect(ClaudeChats.chats(fromBlob: data) == nil)
    }

    @Test func chatsStartSwitchedOffAndCoworkOn() {
        #expect(Agent.chat.onByDefault == false)
        #expect(Agent.cowork.onByDefault)
    }
}
