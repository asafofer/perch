import Foundation

/// What the Claude app keeps of claude.ai on this Mac: its chats and its tasks (what was Cowork). Both live on Anthropic's
/// servers; the app keeps its last fetch of each list in claude.ai's IndexedDB as a persisted react-query cache (one blob,
/// `IndexedDB/https_claude.ai_0.indexeddb.blob/*/*/*`), refreshed while the app runs. Read only: Perch never writes there,
/// never touches the app's login, and never asks the servers itself.
/// - `chat_conversation_list`: the 30 newest chats, titles and times; `project_list` names their Claude projects.
/// - `cowork-remote-sessions` (tasks run in the cloud) and `cowork-local-sessions`: each task's title, folders, times, its
///   live state (`running`, `awaiting` an approval, `idle`) and whether you have seen its latest (`unread`).
public final class ClaudeCache: @unchecked Sendable {
    public struct Chat: Sendable, Equatable {
        public let id: String
        public let title: String
        public let updated: Date
        public let created: Date?
        /// The Claude project it is in, by name, when it is in one.
        public let project: String?
        public let starred: Bool
    }
    public struct Task: Sendable, Equatable {
        public enum State: String, Sendable { case running, awaiting, idle }
        public let id: String
        public let title: String
        /// The folders you gave it; empty when it works without one.
        public let folders: [String]
        public let created: Date?
        public let lastActivity: Date
        public let state: State
        /// Something happened that you have not looked at in the app.
        public let unread: Bool
        public let archived: Bool
    }
    public struct Contents: Sendable, Equatable {
        public var chats: [Chat] = []
        public var tasks: [Task] = []
        public init(chats: [Chat] = [], tasks: [Task] = []) { self.chats = chats; self.tasks = tasks }
    }

    public static let shared = ClaudeCache(root: FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude/IndexedDB/https_claude.ai_0.indexeddb.blob"))
    let root: URL
    private var cache: (path: String, mtime: Date, contents: Contents, read: Date)?
    private let lock = NSLock()
    /// The app rewrites the file whenever any of its queries changes, and reading it takes a moment, so it is read at most
    /// this often. Often enough that a task's working, waiting and done keep pace with the list.
    public var every: TimeInterval = 5

    public init(root: URL) { self.root = root }

    /// Whether claude.ai was ever opened in the Claude app on this Mac.
    public var present: Bool { FileManager.default.fileExists(atPath: root.path) }

    /// The newest blob that holds the persisted query cache. Chromium writes a new file for each version of a large value.
    func cacheFile() -> (URL, Date)? {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]) else { return nil }
        var best: (URL, Date)?
        for case let url as URL in e {
            guard let m = SessionScanner.mtime(url), best.map({ m > $0.1 }) ?? true,
                  let h = try? FileHandle(forReadingFrom: url) else { continue }
            let head = (try? h.read(upToCount: 256)) ?? Data(); try? h.close()
            if head.range(of: Data("conversations_v".utf8)) != nil { best = (url, m) }
        }
        return best
    }

    public func read() -> Contents {
        guard let (url, mtime) = cacheFile() else { return Contents() }
        lock.lock(); let hit = cache; lock.unlock()
        if let hit, (hit.path == url.path && hit.mtime == mtime) || Date().timeIntervalSince(hit.read) < every { return hit.contents }
        guard let data = try? Data(contentsOf: url), let contents = Self.contents(fromBlob: data) else { return hit?.contents ?? Contents() }
        lock.lock(); cache = (url.path, mtime, contents, Date()); lock.unlock()
        return contents
    }

    /// The lists out of one IndexedDB value: Blink's envelope, Snappy, then V8's structured clone. Nil when it is not that.
    public static func contents(fromBlob data: Data) -> Contents? {
        let b = [UInt8](data)
        // 0xFF 0x11 0x02: an IndexedDB value compressed with Snappy.
        guard b.count > 3, b[0] == 0xFF, b[1] == 0x11, b[2] == 0x02, let raw = Snappy.decompress(b[3...]) else { return nil }
        var clone = V8Clone(raw)
        guard let root = clone.read() as? [String: Any],
              let queries = (root["clientState"] as? [String: Any])?["queries"] as? [Any] else { return nil }
        /// Every row of a query's data, however it is paged: [row], {data: [row]}, {rows: [row]}, {pages: [[row] or {data}]}.
        func rows(_ data: Any) -> [[String: Any]] {
            if let a = data as? [Any] { return a.compactMap { $0 as? [String: Any] } }
            guard let o = data as? [String: Any] else { return [] }
            if let pages = o["pages"] as? [Any] { return pages.flatMap(rows) }
            return rows(o["data"] ?? o["rows"] ?? o["sessions"] ?? [Any]())
        }
        var projects: [String: String] = [:], chats: [[String: Any]] = [], tasks: [[String: Any]] = []
        for case let q as [String: Any] in queries {
            guard let key = q["queryKey"] as? [Any], let kind = key.first as? String,
                  let data = (q["state"] as? [String: Any])?["data"] else { continue }
            switch kind {
            case "chat_conversation_list":
                // The sidebar's list; one filtered to starred or archived chats is not it.
                let filter: [String: Any] = key.count > 1 ? (key[key.count - 1] as? [String: Any] ?? [:]) : [:]
                if filter["starred"] as? Bool == true || filter["archived"] as? Bool == true { continue }
                chats += rows(data)
            case "project_list":
                for p in rows(data) { if let id = p["uuid"] as? String, let n = p["name"] as? String { projects[id] = n } }
            case "cowork-remote-sessions", "cowork-local-sessions":
                tasks += rows(data)
            default: continue
            }
        }
        var out = Contents(), seen = Set<String>()
        for c in chats {
            guard let id = c["uuid"] as? String, seen.insert(id).inserted, let updated = (c["updated_at"] as? String).flatMap(Self.date) else { continue }
            let name = (c["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled"
            out.chats.append(Chat(id: id, title: name, updated: updated, created: (c["created_at"] as? String).flatMap(Self.date),
                                  project: (c["project_uuid"] as? String).flatMap { projects[$0] }, starred: c["is_starred"] as? Bool ?? false))
        }
        for t in tasks {
            guard let id = t["sessionId"] as? String, seen.insert(id).inserted, let last = Self.millis(t["lastActivityAt"]) else { continue }
            let live = (t["liveStatus"] as? String).flatMap(Task.State.init(rawValue:))
            let state: Task.State = live == .awaiting ? .awaiting : (t["isRunning"] as? Bool == true || live == .running) ? .running : .idle
            out.tasks.append(Task(id: id, title: (t["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled task",
                                  folders: (t["userSelectedFolders"] as? [Any])?.compactMap { $0 as? String } ?? [],
                                  created: Self.millis(t["createdAt"]), lastActivity: last, state: state,
                                  unread: t["unread"] as? Bool ?? false, archived: t["isArchived"] as? Bool ?? false))
        }
        out.chats.sort { $0.updated > $1.updated }
        out.tasks.sort { $0.lastActivity > $1.lastActivity }
        return out
    }

    static func millis(_ v: Any?) -> Date? {
        if let d = v as? Double { return Date(timeIntervalSince1970: d / 1000) }
        if let i = v as? Int { return Date(timeIntervalSince1970: Double(i) / 1000) }
        return nil
    }

    static func date(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        // Six fractional digits ("…19.517611Z") are more than the formatter takes.
        if let dot = s.firstIndex(of: "."), let z = s.lastIndex(where: { $0 == "Z" || $0 == "+" }), dot < z {
            let frac = s[s.index(after: dot)..<z].prefix(3)
            return f.date(from: String(s[..<dot]) + "." + frac + String(s[z...]))
        }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

/// What was said in the Claude app's tasks and chats, where this Mac has it: claude.ai caches the conversations opened lately
/// in its IndexedDB, in LevelDB's files (`https_claude.ai_0.indexeddb.leveldb`) and, for the large ones, in the blob folder.
/// A task's is the Claude Code stream it ran (read like any transcript), a chat's its message tree. Keyed by the
/// conversation's id: a task's session id (`cse_…`), a chat's uuid. Read only, like `ClaudeCache`.
public final class ClaudeWords: @unchecked Sendable {
    public static let shared = ClaudeWords(idb: FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude/IndexedDB"))
    let idb: URL
    private var cache: (stamp: [Date], words: [String: SessionDigest], read: Date)?
    private let lock = NSLock()
    /// Read at most this often: the files change with every message the app shows.
    public var every: TimeInterval = 5

    public init(idb: URL) { self.idb = idb }

    var leveldb: URL { idb.appendingPathComponent("https_claude.ai_0.indexeddb.leveldb") }
    var blobs: URL { idb.appendingPathComponent("https_claude.ai_0.indexeddb.blob") }

    public func read() -> [String: SessionDigest] {
        let fm = FileManager.default
        var files = ((try? fm.contentsOfDirectory(at: leveldb, includingPropertiesForKeys: nil)) ?? []).filter { ["log", "ldb", "sst"].contains($0.pathExtension) }
        if let e = fm.enumerator(at: blobs, includingPropertiesForKeys: nil) { for case let u as URL in e { files.append(u) } }
        let stamp = files.compactMap(SessionScanner.mtime).sorted()
        lock.lock(); let hit = cache; lock.unlock()
        if let hit, hit.stamp == stamp || Date().timeIntervalSince(hit.read) < every { return hit.words }
        var values = Array(LevelDB.read(leveldb).values)
        for f in files where f.path.hasPrefix(blobs.path) { if let d = try? Data(contentsOf: f, options: .alwaysMapped) { values.append(d) } }
        let words = Self.words(values)
        lock.lock(); cache = (stamp, words, Date()); lock.unlock()
        return words
    }

    /// The conversations among IndexedDB values (a version number, then Blink's envelope), newest copy of each.
    static func words(_ values: [Data]) -> [String: SessionDigest] {
        var out: [String: (at: Double, words: SessionDigest)] = [:]
        for v in values {
            // The conversation's id and product come first in its object: only the Claude app's own (`chat`, `cowork`) are
            // decoded, not Claude Code's cloud sessions (`code`) or the app's other caches, which are large.
            guard let head = Self.raw(v, upTo: 160), Self.product(head) != nil, let raw = Self.raw(v), var c = Optional(V8Clone(raw)),
                  let o = c.read() as? [String: Any], let id = o["conversationUuid"] as? String, let tree = o["tree"] as? [String: Any] else { continue }
            let at = (o["writtenAt"] as? Double) ?? 0
            let words = o["product"] as? String == "cowork" ? Self.task(tree) : Self.chat(tree)
            let key = id.hasPrefix("cowork:") ? String(id.dropFirst(7)) : id
            guard let words, (out[key]?.at ?? -1) < at else { continue }
            out[key] = (at, words)
        }
        return out.mapValues(\.words)
    }

    /// One value's structured clone: after its version number, compressed with Snappy (0xFF 0x11 0x02) or as it is. A value
    /// moved to a blob file (0xFF 0x11 0x01) is read there instead.
    static func raw(_ v: Data, upTo cap: Int? = nil) -> [UInt8]? {
        let b = [UInt8](v.prefix(16))
        guard let j = b.firstIndex(of: 0xFF) else { return nil }
        let start = v.startIndex + j
        if j + 2 < b.count, b[j + 1] == 0x11 {
            guard b[j + 2] == 0x02 else { return nil }
            return Snappy.decompress([UInt8](v[(start + 3)...])[...], upTo: cap)
        }
        return cap.map { [UInt8](v[start...].prefix($0)) } ?? [UInt8](v[start...])
    }

    /// "chat" or "cowork" when the value is one of the Claude app's conversations, from the first bytes of its object.
    static func product(_ raw: [UInt8]) -> String? {
        let head = Data(raw.prefix(160))
        guard head.range(of: Data("conversationUuid".utf8)) != nil else { return nil }
        if head.range(of: Data("product\"\u{04}chat".utf8)) != nil { return "chat" }
        if head.range(of: Data("product\"\u{06}cowork".utf8)) != nil { return "cowork" }
        return nil
    }

    /// A task's cached events are the messages its Claude Code run streamed: read as a transcript, they say what it did,
    /// found and asks, the same as for a Code session.
    static func task(_ tree: [String: Any]) -> SessionDigest? {
        guard let events = tree["events"] as? [Any] else { return nil }
        let lines: [String] = events.compactMap { e in
            guard let p = (e as? [String: Any])?["payload"] as? [String: Any], ["user", "assistant"].contains(p["type"] as? String ?? ""),
                  JSONSerialization.isValidJSONObject(p), let d = try? JSONSerialization.data(withJSONObject: p) else { return nil }
            return String(data: d, encoding: .utf8)
        }
        let d = TranscriptParser.digest(lines: lines)
        return d.lastAssistantText == nil && d.lastUserText == nil ? nil : d
    }

    /// A chat's message tree: the branch you are on ends at its current leaf. Its last reply and your message before it.
    static func chat(_ tree: [String: Any]) -> SessionDigest? {
        let byId = tree["messageByUuid"] as? [String: Any] ?? [:], parents = tree["parentByChildUuid"] as? [String: Any] ?? [:]
        var path: [[String: Any]] = []
        var at = tree["current_leaf_message_uuid"] as? String
        while let id = at, let m = byId[id] as? [String: Any], path.count < 4 { path.append(m); at = parents[id] as? String }
        if path.isEmpty { path = ((tree["chat_messages"] as? [Any]) ?? []).compactMap { $0 as? [String: Any] }.reversed() }
        func text(_ m: [String: Any]) -> String? {
            let blocks = (m["content"] as? [Any] ?? []).compactMap { b -> String? in
                guard let b = b as? [String: Any], b["type"] as? String == "text" else { return nil }
                return b["text"] as? String
            }
            let t = blocks.isEmpty ? (m["text"] as? String ?? "") : blocks.joined(separator: "\n\n")
            return t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : t
        }
        var d = SessionDigest()
        if let m = path.first(where: { $0["sender"] as? String == "assistant" }), let t = text(m) {
            d.lastAssistantText = t; d.lastAssistantFull = t
            d.lastTimestamp = (m["created_at"] as? String).flatMap(ClaudeCache.date)
        }
        if let m = path.first(where: { $0["sender"] as? String == "human" }), let t = text(m) { d.lastUserText = t; d.lastUserFull = t; d.lastAsk = t }
        return d.lastAssistantText == nil && d.lastUserText == nil ? nil : d
    }
}

/// Snappy's raw format (no framing), as Chromium writes IndexedDB values.
enum Snappy {
    /// With `upTo`, it stops once that much is out and returns just that: enough to see what a value is before unpacking it.
    static func decompress(_ input: ArraySlice<UInt8>, upTo cap: Int? = nil) -> [UInt8]? {
        let b = Array(input)
        var i = 0
        func varint() -> Int? {
            var r = 0, s = 0
            while i < b.count, s < 35 { let c = Int(b[i]); i += 1; r |= (c & 0x7F) << s; s += 7; if c < 0x80 { return r } }
            return nil
        }
        guard let n = varint(), n < 256 << 20 else { return nil }
        var out = [UInt8](); out.reserveCapacity(n)
        while i < b.count {
            if let cap, out.count >= cap { return out }
            let t = Int(b[i]); i += 1
            if t & 3 == 0 {
                var len = t >> 2
                if len >= 60 {
                    let extra = len - 59
                    guard i + extra <= b.count else { return nil }
                    len = 0; for k in 0..<extra { len |= Int(b[i + k]) << (8 * k) }; i += extra
                }
                len += 1
                guard i + len <= b.count else { return nil }
                out += b[i..<i + len]; i += len
            } else {
                let len: Int, off: Int
                switch t & 3 {
                case 1: guard i < b.count else { return nil }; len = ((t >> 2) & 7) + 4; off = ((t >> 5) << 8) | Int(b[i]); i += 1
                case 2: guard i + 2 <= b.count else { return nil }; len = (t >> 2) + 1; off = Int(b[i]) | Int(b[i + 1]) << 8; i += 2
                default: guard i + 4 <= b.count else { return nil }; len = (t >> 2) + 1; off = Int(b[i]) | Int(b[i + 1]) << 8 | Int(b[i + 2]) << 16 | Int(b[i + 3]) << 24; i += 4
                }
                guard off > 0, off <= out.count else { return nil }
                let start = out.count - off
                for k in 0..<len { out.append(out[start + k]) }
            }
        }
        return out.count == n ? out : nil
    }
}

/// Just enough of V8's structured clone format to read plain JSON-like data: objects, arrays, strings, numbers, booleans,
/// dates and back references. Anything else stops the read (nil).
struct V8Clone {
    private let b: [UInt8]
    private var i = 0
    private var objects: [Any] = []
    init(_ bytes: [UInt8]) { b = bytes }

    mutating func read() -> Any? {
        // Blink's header: 0xFF <version>, then from version 21 a trailer offset (0xFE, 8 + 4 bytes). V8's own 0xFF <version> follows.
        guard b.count > 2, b[0] == 0xFF else { return nil }
        i = 2
        if i < b.count, b[i] == 0xFE { i += 13 }
        return try? value()
    }

    private struct Stop: Error {}
    private mutating func byte() throws -> UInt8 { guard i < b.count else { throw Stop() }; defer { i += 1 }; return b[i] }
    private func peek() throws -> UInt8 { guard i < b.count else { throw Stop() }; return b[i] }
    private mutating func varint() throws -> Int {
        var r = 0, s = 0
        while s < 63 { let c = Int(try byte()); r |= (c & 0x7F) << s; s += 7; if c < 0x80 { return r } }
        throw Stop()
    }
    private mutating func bytes(_ n: Int) throws -> ArraySlice<UInt8> { guard n >= 0, i + n <= b.count else { throw Stop() }; defer { i += n }; return b[i..<i + n] }
    private mutating func double() throws -> Double {
        let s = try bytes(8); var v: UInt64 = 0
        for (k, x) in s.enumerated() { v |= UInt64(x) << (8 * UInt64(k)) }
        return Double(bitPattern: v)
    }
    private mutating func key() throws -> String {
        let k = try value()
        if let s = k as? String { return s }
        if let n = k as? Int { return String(n) }
        if let d = k as? Double { return String(Int(d)) }
        throw Stop()
    }

    private mutating func value() throws -> Any {
        let t = try byte()
        switch t {
        case 0xFF: _ = try varint(); return try value()
        case 0x00: return try value()                               // padding
        case UInt8(ascii: "\""): let n = try varint(); return String(String.UnicodeScalarView(try bytes(n).map { Unicode.Scalar($0) }))
        case UInt8(ascii: "c"):
            let n = try varint(); let s = try bytes(n)
            return String(decoding: stride(from: s.startIndex, to: s.endIndex - 1, by: 2).map { UInt16(b[$0]) | UInt16(b[$0 + 1]) << 8 }, as: UTF16.self)
        case UInt8(ascii: "S"): let n = try varint(); return String(decoding: try bytes(n), as: UTF8.self)
        case UInt8(ascii: "I"): let n = try varint(); return (n >> 1) ^ -(n & 1)
        case UInt8(ascii: "U"): return try varint()
        case UInt8(ascii: "N"): return try double()
        case UInt8(ascii: "D"): return Date(timeIntervalSince1970: try double() / 1000)
        case UInt8(ascii: "T"): return true
        case UInt8(ascii: "F"): return false
        case UInt8(ascii: "_"), UInt8(ascii: "0"): return NSNull()
        case UInt8(ascii: "^"): let id = try varint(); guard id < objects.count else { throw Stop() }; return objects[id]
        case UInt8(ascii: "o"):
            let slot = objects.count; objects.append(NSNull())
            var o: [String: Any] = [:]
            while try peek() != UInt8(ascii: "{") { let k = try key(); o[k] = try value() }
            i += 1; _ = try varint(); objects[slot] = o; return o
        case UInt8(ascii: ";"):
            let slot = objects.count; objects.append(NSNull())
            var o: [String: Any] = [:]
            while try peek() != UInt8(ascii: ":") { let k = try key(); o[k] = try value() }
            i += 1; _ = try varint(); objects[slot] = o; return o
        case UInt8(ascii: "A"):
            let slot = objects.count; objects.append(NSNull())
            let n = try varint(); var a: [Any] = []; a.reserveCapacity(min(n, 4096))
            for _ in 0..<n { a.append(try value()) }
            while try peek() != UInt8(ascii: "$") { _ = try key(); _ = try value() }
            i += 1; _ = try varint(); _ = try varint(); objects[slot] = a; return a
        case UInt8(ascii: "a"):
            let slot = objects.count; objects.append(NSNull())
            let n = try varint(); guard n < 1 << 20 else { throw Stop() }
            var a = [Any](repeating: NSNull(), count: n)
            while try peek() != UInt8(ascii: "@") { let k = try key(); let v = try value(); if let x = Int(k), x < n { a[x] = v } }
            i += 1; _ = try varint(); _ = try varint(); objects[slot] = a; return a
        case UInt8(ascii: "'"):
            let slot = objects.count; objects.append(NSNull())
            var a: [Any] = []
            while try peek() != UInt8(ascii: ",") { a.append(try value()) }
            i += 1; _ = try varint(); objects[slot] = a; return a
        default: throw Stop()
        }
    }
}
