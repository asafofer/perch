import Foundation

/// Grok Bot's bots, from what its app keeps on this Mac (~/Library/Application Support/Grok Bot/sand-client-persistence).
/// The bots run in the cloud, each one long chat; the app writes its list and the recent part of each chat while it runs.
/// Each file is one slice, `{"schemaVersion", "value"}`, named by its key in lower-case base32 without padding, plus `.blob`.
/// Keys are `sand.client.slice.account.<account, URL-encoded>.<slice>`; the account in use is in
/// `sand.client.slice.client-meta.account-slot`. Read only.
public final class GrokBotStore: @unchecked Sendable {
    public struct Bot: Equatable, Sendable {
        public let id: String
        public let name: String
        public let created: Date?
        public let lastActivity: Date
        public let unread: Bool
        /// Why it waits on you, in its own words, when it does (`awaitingUserResponse`).
        public let waiting: String?
        /// Its newest message, as the list shows it.
        public let lastText: String?
        /// Its avatar, "shape:color", as Grok Bot draws it (`look`).
        public var avatar: String = ""
    }

    /// The shape and colour Grok Bot gives a bot: the ones you chose, else ones picked from its id, by Grok Bot's own rule
    /// (its renderer's `An`: an FNV-1a hash of the id, a mixer for the shape, mulberry32 for the colour).
    public static let shapes = ["blob", "pebble", "bean", "egg", "squircle", "tablet", "capsule", "cylinder", "hex", "gem", "crystal", "wedge",
                                "shield", "dome", "arch", "cloud", "teardrop", "leaf", "square", "sparkle", "clover", "flower", "heart", "house", "star", "pumpkin"]
    static let defaultShapes = ["blob", "pebble", "squircle", "tablet", "wedge", "hex", "cloud", "teardrop"]
    public static let colors = ["black", "brown", "red", "orange", "yellow", "green", "cyan", "blue", "violet", "magenta", "gray"]
    public static func look(id: String, shape: String?, color: String?) -> String {
        func fnv(_ s: String) -> UInt32 { var t: UInt32 = 2166136261; for u in s.utf16 { t ^= UInt32(u); t = t &* 16777619 }; return t }
        let h = fnv(id)
        var m = h; m = (m ^ (m >> 16)) &* 73244475; m = (m ^ (m >> 13)) &* 3266489909; m ^= m >> 16
        // mulberry32's first draw, seeded with the hash (the two xors with 2654435769 on the way cancel out)
        var t = h &+ 1831565813
        var e = (t ^ (t >> 15)) &* (1 | t)
        e = (e &+ ((e ^ (e >> 7)) &* (61 | e))) ^ e
        t = e ^ (e >> 14)
        let palette = colors.filter { $0 != "black" }
        let s = shape.flatMap { shapes.contains($0) ? $0 : nil } ?? defaultShapes[Int(m % UInt32(defaultShapes.count))]
        let c = color.flatMap { colors.contains($0) ? $0 : nil } ?? palette[Int(Double(t) / 4_294_967_296 * Double(palette.count))]
        return s + ":" + c
    }

    let root: URL
    public init(root: URL) { self.root = root }
    public static let shared = GrokBotStore(root: FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Grok Bot/sand-client-persistence"))

    /// A slice's file name: its key in lower-case base32, no padding.
    static func fileName(_ key: String) -> String { base32(Array(key.utf8)).lowercased() + ".blob" }
    static func base32(_ bytes: [UInt8]) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var out = "", buffer = 0, bits = 0
        for b in bytes {
            buffer = (buffer << 8) | Int(b); bits += 8
            while bits >= 5 { out.append(alphabet[(buffer >> (bits - 5)) & 31]); bits -= 5 }
        }
        if bits > 0 { out.append(alphabet[(buffer << (5 - bits)) & 31]) }
        return out
    }

    private func slice(_ key: String) -> Any? {
        guard let data = try? Data(contentsOf: root.appendingPathComponent(Self.fileName(key))),
              let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return o["value"]
    }
    private var account: String? {
        guard let a = slice("sand.client.slice.client-meta.account-slot") as? String, !a.isEmpty else { return nil }
        return a.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_.~")))
    }
    private func accountSlice(_ name: String) -> Any? { account.flatMap { slice("sand.client.slice.account.\($0).\(name)") } }

    /// Every bot in the sidebar, newest first. Hidden and removed ones, and rooms of several bots, are left out.
    public func bots() -> [Bot] {
        guard let rows = (accountSlice("roster.last-roster") as? [String: Any])?["rows"] as? [[String: Any]] else { return [] }
        func date(_ v: Any?) -> Date? { (v as? Double).map { Date(timeIntervalSince1970: $0 / 1000) } }
        return rows.compactMap { r -> Bot? in
            guard let id = r["id"] as? String, r["isHiddenFromSidebar"] as? Bool != true, r["isRemovedFromSidebar"] as? Bool != true,
                  r["isGroup"] as? Bool != true, let at = date(r["lastActivityAt"]) ?? date(r["updatedAt"]) else { return nil }
            let name = ((r["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let waiting = (r["awaitingUserResponse"] as? [String: Any]).map { ($0["reasonCopy"] as? String) ?? ($0["reason"] as? String) ?? "" }
            var bot = Bot(id: id, name: name.isEmpty ? "Grok Bot" : name, created: date(r["createdAt"]), lastActivity: at,
                          unread: r["hasUnread"] as? Bool ?? false, waiting: waiting, lastText: (r["lastEntry"] as? [String: Any])?["text"] as? String)
            bot.avatar = Self.look(id: id, shape: r["avatarShape"] as? String, color: r["avatarColor"] as? String)
            return bot
        }.sorted { $0.lastActivity > $1.lastActivity }
    }

    /// What was said lately with a bot, from the app's copy of its chat (the latest entries only; no tool calls, no turn ends).
    /// Nil for a bot not opened on this Mac. Read again only when its file changed.
    public func words(bot id: String) -> SessionDigest? {
        guard let account else { return nil }
        let url = root.appendingPathComponent(Self.fileName("sand.client.slice.account.\(account).transcript.replicas.\(id)"))
        guard let m = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return nil }
        lock.lock(); let hit = wordsCache[url.path]; lock.unlock()
        if let hit, hit.mtime == m { return hit.digest }
        guard let data = try? Data(contentsOf: url), let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let entries = (o["value"] as? [String: Any])?["entries"] as? [[String: Any]] else { return nil }
        let d = Self.digest(entries)
        lock.lock(); wordsCache[url.path] = (m, d); lock.unlock()
        return d
    }
    private var wordsCache: [String: (mtime: Date, digest: SessionDigest)] = [:]
    private let lock = NSLock()

    static func digest(_ entries: [[String: Any]]) -> SessionDigest {
        var d = SessionDigest()
        var leavesOnMoveOn = false   // the open card goes away once the bot says something else (`dismissOnMoveOn`)
        for e in entries {
            let at = (e["timestampMs"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
            switch e["kind"] as? String {
            case "message" where e["role"] as? String == "user" && e["fromAgent"] == nil:
                guard let raw = e["content"] as? String, let t = TranscriptParser.text(from: raw), !t.isEmpty else { continue }
                d.lastUserText = t; d.lastUserFull = TranscriptParser.text(from: raw, keepLines: true); d.lastAsk = t
                d.lastRole = "user"; d.lastTimestamp = at ?? d.lastTimestamp; d.pendingTool = nil
            case "send-message":
                guard let m = e["message"] as? [String: Any] else { continue }
                switch m["type"] as? String {
                case "text":
                    guard let raw = m["content"] as? String, let t = TranscriptParser.text(from: raw), !t.isEmpty else { continue }
                    d.lastAssistantText = t; d.lastAssistantFull = TranscriptParser.text(from: raw, keepLines: true)
                    d.lastRole = "assistant"; d.lastTimestamp = at ?? d.lastTimestamp
                    if leavesOnMoveOn { d.pendingTool = nil; leavesOnMoveOn = false }
                case "widget":
                    // A question with choices, open until you pick one or skip it.
                    // The entry carries what became of it (`respondedValue`, `widgetSkipped`).
                    guard let w = m["widget"] as? [String: Any], e["respondedValue"] == nil, e["widgetSkipped"] == nil else { d.pendingTool = nil; continue }
                    let options = (w["options"] as? [[String: Any]] ?? []).compactMap { $0["label"] as? String }.map { ["label": $0] }
                    let q: [String: Any] = ["questions": [["question": w["prompt"] as? String ?? "A question for you", "options": options]]]
                    d.pendingTool = PendingTool(block: ["name": "AskUserQuestion", "input": q])
                    leavesOnMoveOn = w["dismissOnMoveOn"] as? Bool == true
                    d.lastTimestamp = at ?? d.lastTimestamp
                default: continue
                }
            default: continue
            }
        }
        return d
    }
}

/// OpenAI's Dots, from what the ChatGPT app (the Codex app's bundle) keeps on this Mac: `~/.codex/.codex-global-state.json`,
/// under `electron-persisted-atom-state`. A dot runs in OpenAI's cloud as one long chat; the app saves its profile (name,
/// paused, the newest message) when it shows Dots: `cloud-aeon-sidebar-cache-v1` (`profilesByThreadId`, the same dot under
/// each of its threads) and `primary-aeon-selection-v1` (`response.profile`). The newer copy of a dot wins. Read only.
public final class DotsStore: @unchecked Sendable {
    public struct Dot: Equatable, Sendable {
        public let id: String
        public let name: String
        public let created: Date?
        public let lastActivity: Date
        public let paused: Bool
        public let unread: Bool
        /// The newest message, cut where the app cuts it (about 100 characters).
        public let preview: String?
    }

    let url: URL
    public init(url: URL) { self.url = url }
    public static let shared = DotsStore(url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/.codex-global-state.json"))

    private var cache: (mtime: Date, dots: [Dot])?
    private let lock = NSLock()

    public func dots() -> [Dot] {
        guard let m = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return [] }
        lock.lock(); let hit = cache; lock.unlock()
        if let hit, hit.mtime == m { return hit.dots }
        let found = read()
        lock.lock(); cache = (m, found); lock.unlock()
        return found
    }

    private func read() -> [Dot] {
        guard let data = try? Data(contentsOf: url), let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let state = o["electron-persisted-atom-state"] as? [String: Any] else { return [] }
        func value(_ k: String) -> [String: Any]? {
            if let d = state[k] as? [String: Any] { return d }
            if let s = state[k] as? String { return (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any] }
            return nil
        }
        var profiles = Array(((value("cloud-aeon-sidebar-cache-v1")?["profilesByThreadId"] as? [String: Any]) ?? [:]).values.compactMap { $0 as? [String: Any] })
        if let p = (value("primary-aeon-selection-v1")?["response"] as? [String: Any])?["profile"] as? [String: Any] { profiles.append(p) }
        // The newest copy of a dot wins; its newest message comes from whichever copy has one (the primary dot's has none).
        var byId: [String: Dot] = [:]
        for p in profiles {
            guard let id = p["id"] as? String, p["status"] as? String != "deleting", let dot = Self.dot(p, id: id) else { continue }
            guard let had = byId[id] else { byId[id] = dot; continue }
            let (new, old) = dot.lastActivity > had.lastActivity ? (dot, had) : (had, dot)
            byId[id] = new.preview != nil ? new : Dot(id: id, name: new.name, created: new.created ?? old.created, lastActivity: new.lastActivity,
                                                     paused: new.paused, unread: old.unread, preview: old.preview)
        }
        return byId.values.sorted { $0.lastActivity > $1.lastActivity }
    }

    static func dot(_ p: [String: Any], id: String) -> Dot? {
        let room = p["messaging_room_preview"] as? [String: Any], preview = room?["message_preview"] as? [String: Any]
        let newest = (preview?["latest_item_timestamp"] as? String).flatMap(date)
        guard let at = [newest, (p["last_check_in_at"] as? String).flatMap(date), (p["updated_at"] as? String).flatMap(date)].compactMap({ $0 }).max() else { return nil }
        let read = (room?["last_read_at"] as? String).flatMap(date)
        let name = ((p["display_name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return Dot(id: id, name: name.isEmpty ? "Dots" : name, created: (p["created_at"] as? String).flatMap(date), lastActivity: at,
                   paused: p["is_paused"] as? Bool ?? false, unread: newest.map { n in read.map { n > $0 } ?? true } ?? false,
                   preview: (preview?["preview"] as? String).flatMap { $0.isEmpty ? nil : $0 })
    }

    /// "2026-10-14T10:02:49.867829Z": six fractional digits, which ISO8601DateFormatter does not read.
    static func date(_ s: String) -> Date? {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        if let dot = s.firstIndex(of: "."), let z = s.lastIndex(where: { $0 == "Z" || $0 == "+" }), dot < z {
            let frac = s[s.index(after: dot)..<z].prefix(3)
            return f.date(from: String(s[..<dot]) + "." + frac + String(s[z...]))
        }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
