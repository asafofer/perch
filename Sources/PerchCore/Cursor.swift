import Foundation
import SQLite3

/// Cursor keeps what was said in plain files (~/.cursor/projects/<folder>/agent-transcripts/<id>/<id>.jsonl) and everything
/// else about a chat in one SQLite database (Application Support/Cursor/User/globalStorage/state.vscdb): its title in
/// `composerData:<id>`, its folder and whether it is archived in the `composerHeaders` table. The database can grow to
/// gigabytes and Cursor writes to it all the time, so Perch opens it read-only for each scan, asks for single rows by key
/// and never walks it. It also holds the chats' encryption keys: only the named fields are ever taken from a row.
public final class CursorStore {
    public struct Header: Equatable, Sendable {
        public let workspaceId: String?
        public let archived: Bool
        public let subagent: Bool
    }
    public struct Chat: Equatable, Sendable {
        public let name: String?
        public let workspaceId: String?
        public let unread: Bool
    }

    private var db: OpaquePointer?
    private let user: URL

    /// `user`: Cursor's Application Support folder for the signed-in profile (…/Cursor/User).
    public init?(user: URL) {
        self.user = user
        let file = user.appendingPathComponent("globalStorage/state.vscdb")
        guard FileManager.default.fileExists(atPath: file.path),
              sqlite3_open_v2(file.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { sqlite3_close(db); return nil }
        sqlite3_busy_timeout(db, 250)
    }
    deinit { sqlite3_close(db) }

    /// The list's row for a chat. Nil on a Cursor that predates the table (the chat's folder then comes from the transcript's own folder).
    public func header(_ id: String) -> Header? {
        var out: Header?
        query("SELECT workspaceId, isArchived, isSubagent FROM composerHeaders WHERE composerId = ?", id) { st in
            out = Header(workspaceId: Self.text(st, 0), archived: sqlite3_column_int(st, 1) != 0, subagent: sqlite3_column_int(st, 2) != 0)
        }
        return out
    }

    /// The title and folder of a chat, from its `composerData` row. The row can be large (it carries every file the chat
    /// touched), so this is asked for only when the transcript changed.
    public func chat(_ id: String) -> Chat? {
        var out: Chat?
        query("SELECT CAST(value AS TEXT) FROM cursorDiskKV WHERE key = ?", "composerData:" + id) { st in
            guard let json = Self.text(st, 0), let o = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] else { return }
            let name = (o["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            out = Chat(name: name?.isEmpty == false ? name : nil, workspaceId: (o["workspaceIdentifier"] as? [String: Any])?["id"] as? String,
                       unread: o["hasUnreadMessages"] as? Bool ?? false)
        }
        return out
    }

    /// The folder a window of Cursor had open: workspaceStorage/<id>/workspace.json holds `{"folder": "file:///…"}`.
    /// Nil for a window with no folder ("empty-window") or a multi-root workspace file.
    public func folder(workspace id: String) -> String? {
        guard id != "empty-window", !id.contains("/") else { return nil }
        let file = user.appendingPathComponent("workspaceStorage/\(id)/workspace.json")
        guard let data = try? Data(contentsOf: file), let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let folder = o["folder"] as? String, let url = URL(string: folder), url.isFileURL else { return nil }
        return url.path
    }

    private func query(_ sql: String, _ key: String, _ row: (OpaquePointer) -> Void) {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK, let st else { return }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_text(st, 1, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        if sqlite3_step(st) == SQLITE_ROW { row(st) }
    }
    private static func text(_ st: OpaquePointer, _ i: Int32) -> String? { sqlite3_column_text(st, i).map { String(cString: $0) } }
}

public enum CursorApp {
    public static let bundle = "com.todesktop.230313mzl4w4u92"
    /// Chats started in a window with no folder open are kept under this transcript folder.
    public static let noFolder = "empty-window"

    /// The folder a transcript folder was named after: its path with every "/" and other symbol as "-" and dots dropped
    /// (`/Users/a/Desktop/my app/.x` is `Users-a-Desktop-my-app-x`). That loses which dashes were slashes, so the real
    /// folders are walked to find the one it names. Used only when the database does not say.
    public static func folder(forSlug slug: String, fm: FileManager = .default) -> String? {
        func norm(_ s: String) -> String {
            String(s.replacingOccurrences(of: ".", with: "").map { $0.isLetter && $0.isASCII || $0.isNumber ? $0 : "-" })
        }
        func walk(_ base: String, _ rest: String) -> String? {
            guard let names = try? fm.contentsOfDirectory(atPath: base) else { return nil }
            for name in names.sorted() {
                let n = norm(name)
                guard !n.isEmpty, rest == n || rest.hasPrefix(n + "-") else { continue }
                let path = (base as NSString).appendingPathComponent(name)
                if rest == n { return path }
                if let hit = walk(path, String(rest.dropFirst(n.count + 1))) { return hit }
            }
            return nil
        }
        return slug.isEmpty ? nil : walk("/", slug)
    }
}

/// Reads a Cursor transcript. It keeps what was said and the tool calls (name and input), and one `turn_ended` line when the
/// agent finishes. It has no times, no tool results and no folder: the file's age says when, and the database says where.
public enum CursorTranscript {
    public static func digest(lines: [String]) -> SessionDigest {
        var d = SessionDigest()
        // The last tool call, until something follows it: a transcript has no results, so a call that the next line does not
        // follow is still running, or waiting for your OK.
        var open: PendingTool?
        for line in lines {
            guard let o = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { continue }
            if o["type"] as? String == "turn_ended" {
                d.turnOpen = false; open = nil
                // Cursor closes a turn you stopped, or one it found left open, as an error that says so.
                let why = o["error"] as? String
                switch o["status"] as? String {
                case "aborted", "cancelled", "canceled": d.interrupted = true
                case "error", "failed":
                    if why?.lowercased().contains("abort") == true { d.interrupted = true } else { d.failed = why ?? "error" }
                default: break
                }
                continue
            }
            guard let role = o["role"] as? String, let m = o["message"] as? [String: Any] else { continue }
            let blocks = m["content"] as? [[String: Any]] ?? []
            let texts = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }
            if role == "user" {
                let words = texts.map(query(in:)).joined(separator: "\n\n")
                guard let line = TranscriptParser.text(from: words), !line.isEmpty else { continue }
                d.turnOpen = true; d.interrupted = false; d.stoppedAt = nil; d.failed = nil; open = nil
                d.lastUserText = line; d.lastUserFull = TranscriptParser.text(from: words, keepLines: true)
                if !Recap.isAcknowledgement(line) { d.lastAsk = line }
                d.narration = nil; d.step = nil; d.work = Work()
                d.lastRole = "user"
                d.recent.append(.init(role: "user", text: Recap.clip(line, 420)))
            } else if role == "assistant" {
                open = nil
                for b in blocks where b["type"] as? String == "tool_use" {
                    let name = b["name"] as? String ?? "tool", input = b["input"] as? [String: Any] ?? [:]
                    d.didWork = true
                    if let step = Activity.step(tool: name, input: input) { d.step = step }
                    d.work.note(tool: name, input: input)
                }
                if let last = blocks.last, last["type"] as? String == "tool_use" { open = PendingTool(block: last) }
                let words = texts.map(clean).joined(separator: "\n\n")
                guard let line = TranscriptParser.text(from: words), !line.isEmpty else { continue }
                d.lastAssistantText = line; d.lastAssistantFull = TranscriptParser.text(from: words, keepLines: true); d.narration = line
                d.lastRole = "assistant"
                d.recent.append(.init(role: "assistant", text: Recap.clip(line, 420)))
            }
            if d.recent.count > 12 { d.recent.removeFirst() }
        }
        d.pendingTool = d.turnOpen ? open : nil
        return d
    }

    /// Cursor wraps your prompt in `<user_query>` and puts a `<timestamp>` and other context before it.
    static func query(in text: String) -> String {
        if let a = text.range(of: "<user_query>"), let b = text.range(of: "</user_query>", range: a.upperBound..<text.endIndex) {
            return String(text[a.upperBound..<b.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    /// Cursor marks what it left out of a reply (its reasoning) as "[REDACTED]".
    static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "[REDACTED]", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
