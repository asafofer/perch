import Foundation

/// Cowork, the Claude app's agent for everyday work. Each task is a Claude Code session the app runs for you, kept in
/// `local-agent-mode-sessions/<account>/<org>/local_<id>.json` beside a folder of the same name that holds its own
/// `.claude/projects/*/<cliSessionId>.jsonl`, written like any Claude Code transcript (`entrypoint: local-agent`).
public final class CoworkSessions: @unchecked Sendable {
    public struct Entry: Sendable {
        public let id: String
        public let title: String?
        /// The folders you gave it. Without one it works in its own `outputs` folder.
        public let folders: [String]
        public let cwd: String?
        public let archived: Bool
        public let transcript: URL?
        public let lastActivity: Date?
    }
    public static let shared = CoworkSessions(root: FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude/local-agent-mode-sessions"))
    let root: URL
    private var cache: [String: (mtime: Date, entry: Entry)] = [:]
    private let lock = NSLock()

    public init(root: URL) { self.root = root }

    /// Whether Cowork was ever used on this Mac.
    public var present: Bool { FileManager.default.fileExists(atPath: root.path) }

    public func index() -> [Entry] {
        let fm = FileManager.default
        lock.lock(); defer { lock.unlock() }
        var fresh: [String: (mtime: Date, entry: Entry)] = [:]
        for account in (try? fm.contentsOfDirectory(atPath: root.path)) ?? [] {
            let accountDir = root.appendingPathComponent(account)
            for org in (try? fm.contentsOfDirectory(atPath: accountDir.path)) ?? [] {
                let dir = accountDir.appendingPathComponent(org)
                for file in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where file.hasPrefix("local_") && file.hasSuffix(".json") {
                    let url = dir.appendingPathComponent(file)
                    guard let mtime = SessionScanner.mtime(url) else { continue }
                    if let hit = cache[url.path], hit.mtime == mtime { fresh[url.path] = hit; continue }
                    guard let data = try? Data(contentsOf: url),
                          let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                          let id = o["sessionId"] as? String else { continue }
                    let folder = dir.appendingPathComponent(String(file.dropLast(5)))
                    let transcript = (o["cliSessionId"] as? String).flatMap { cli -> URL? in
                        let projects = folder.appendingPathComponent(".claude/projects")
                        for d in (try? fm.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? [] {
                            let f = d.appendingPathComponent(cli + ".jsonl")
                            if fm.fileExists(atPath: f.path) { return f }
                        }
                        return nil
                    }
                    let last = (o["lastActivityAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
                    fresh[url.path] = (mtime, Entry(id: id, title: o["title"] as? String, folders: o["userSelectedFolders"] as? [String] ?? [],
                                                    cwd: o["cwd"] as? String, archived: o["isArchived"] as? Bool ?? false,
                                                    transcript: transcript, lastActivity: last))
                }
            }
        }
        cache = fresh
        return fresh.values.map(\.entry)
    }
}

/// The chats in the Claude app (claude.ai). They live on Anthropic's servers; the app keeps its last fetch of the recent list
/// (`chat_conversation_list`, 30 newest) in claude.ai's IndexedDB as a persisted react-query cache, refreshed while it runs.
/// Only titles and times are there, no messages, and only for the account last signed in.
public final class ClaudeChats: @unchecked Sendable {
    public struct Chat: Sendable, Equatable {
        public let id: String
        public let title: String
        public let updated: Date
        public let created: Date?
        /// The Claude project it is in, by name, when it is in one.
        public let project: String?
        public let starred: Bool
    }
    public static let shared = ClaudeChats(root: FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude/IndexedDB/https_claude.ai_0.indexeddb.blob"))
    let root: URL
    private var cache: (path: String, mtime: Date, chats: [Chat], read: Date)?
    private let lock = NSLock()
    /// The app rewrites the file whenever any of its queries changes, and reading it takes a moment, so it is read at most
    /// this often. A chat's title and time are not urgent.
    public var every: TimeInterval = 30

    public init(root: URL) { self.root = root }

    /// The newest blob that holds the persisted query cache. Chromium writes a new file for each version of a large value.
    func cacheFile() -> (URL, Date)? {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]) else { return nil }
        var best: (URL, Date)?
        for case let url as URL in e {
            guard let m = SessionScanner.mtime(url), best.map({ m > $0.1 }) ?? true,
                  let h = try? FileHandle(forReadingFrom: url) else { continue }
            let head = (try? h.read(upToCount: 96)) ?? Data(); try? h.close()
            if head.range(of: Data("conversations_v".utf8)) != nil { best = (url, m) }
        }
        return best
    }

    public func recent() -> [Chat] {
        guard let (url, mtime) = cacheFile() else { return [] }
        lock.lock(); let hit = cache; lock.unlock()
        if let hit, (hit.path == url.path && hit.mtime == mtime) || Date().timeIntervalSince(hit.read) < every { return hit.chats }
        guard let data = try? Data(contentsOf: url), let chats = Self.chats(fromBlob: data) else { return hit?.chats ?? [] }
        lock.lock(); cache = (url.path, mtime, chats, Date()); lock.unlock()
        return chats
    }

    /// The chat list out of one IndexedDB value: Blink's envelope, Snappy, then V8's structured clone.
    public static func chats(fromBlob data: Data) -> [Chat]? {
        let b = [UInt8](data)
        // 0xFF 0x11 0x02: an IndexedDB value compressed with Snappy.
        guard b.count > 3, b[0] == 0xFF, b[1] == 0x11, b[2] == 0x02, let raw = Snappy.decompress(b[3...]) else { return nil }
        var clone = V8Clone(raw)
        guard let root = clone.read() as? [String: Any],
              let queries = (root["clientState"] as? [String: Any])?["queries"] as? [Any] else { return nil }
        var projects: [String: String] = [:]
        var lists: [[String: Any]] = []
        for case let q as [String: Any] in queries {
            guard let key = q["queryKey"] as? [Any], let kind = key.first as? String,
                  let data = (q["state"] as? [String: Any])?["data"] else { continue }
            switch kind {
            case "chat_conversation_list":
                // The infinite list ({pages: [[chat]]}) is the sidebar's; a plain one ({data: [chat]}) is a filter (starred).
                let filter: [String: Any] = key.count > 1 ? (key[key.count - 1] as? [String: Any] ?? [:]) : [:]
                if filter["starred"] as? Bool == true || filter["archived"] as? Bool == true { continue }
                let box = data as? [String: Any] ?? [:]
                for page in box["pages"] as? [Any] ?? [box["data"] as Any] {
                    let rows: [Any] = page as? [Any] ?? ((page as? [String: Any])?["data"] as? [Any]) ?? []
                    lists += rows.compactMap { $0 as? [String: Any] }
                }
            case "project_list":
                let box = data as? [String: Any] ?? [:]
                var rows: [Any] = data as? [Any] ?? []
                for page in box["pages"] as? [Any] ?? [] { rows += page as? [Any] ?? ((page as? [String: Any])?["data"] as? [Any]) ?? [] }
                for case let p as [String: Any] in rows { if let id = p["uuid"] as? String, let n = p["name"] as? String { projects[id] = n } }
            default: continue
            }
        }
        var seen = Set<String>(), out: [Chat] = []
        for c in lists {
            guard let id = c["uuid"] as? String, seen.insert(id).inserted, let updated = (c["updated_at"] as? String).flatMap(Self.date) else { continue }
            let name = (c["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled"
            out.append(Chat(id: id, title: name, updated: updated, created: (c["created_at"] as? String).flatMap(Self.date),
                            project: (c["project_uuid"] as? String).flatMap { projects[$0] }, starred: c["is_starred"] as? Bool ?? false))
        }
        return out.sorted { $0.updated > $1.updated }
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

/// Snappy's raw format (no framing), as Chromium writes IndexedDB values.
enum Snappy {
    static func decompress(_ input: ArraySlice<UInt8>) -> [UInt8]? {
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
