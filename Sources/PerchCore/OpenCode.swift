import Foundation
import SQLite3

/// OpenCode keeps every session in one SQLite database (~/.local/share/opencode/opencode.db), shared by its terminal app
/// and its desktop app. Perch opens it read-only for each scan and closes it again, so it never holds OpenCode up.
public final class OpenCodeStore {
    public struct Session: Equatable, Sendable {
        public let id: String
        public let directory: String
        public let title: String
        /// The newest change to the session or any of its messages.
        public let updated: Date
        public let created: Date
    }
    /// One message and its parts, oldest first: the JSON OpenCode stores, as dictionaries.
    public struct Message { public let data: [String: Any]; public let parts: [[String: Any]]; public let created: Date }

    private var db: OpaquePointer?

    public init?(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path),
              sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { sqlite3_close(db); return nil }
        sqlite3_busy_timeout(db, 250)
    }
    deinit { sqlite3_close(db) }

    /// Sessions you started (not a subagent's), not archived, changed since `after`, newest first.
    public func sessions(after: Date, limit: Int) -> [Session] {
        let sql = """
            SELECT s.id, s.directory, s.title, max(s.time_updated, coalesce((SELECT max(m.time_updated) FROM message m WHERE m.session_id = s.id), 0)) AS t, s.time_created
            FROM session s WHERE s.parent_id IS NULL AND s.time_archived IS NULL AND s.time_updated > ?
            ORDER BY t DESC LIMIT ?
            """
        return rows(sql, bind: [.int(Int64(after.timeIntervalSince1970 * 1000)), .int(Int64(limit))]) { st in
            Session(id: Self.text(st, 0), directory: Self.text(st, 1), title: Self.text(st, 2),
                    updated: Date(timeIntervalSince1970: Double(sqlite3_column_int64(st, 3)) / 1000),
                    created: Date(timeIntervalSince1970: Double(sqlite3_column_int64(st, 4)) / 1000))
        }
    }

    /// The session's last `last` messages with their parts, oldest first.
    public func messages(session: String, last: Int = 40) -> [Message] {
        let sql = """
            SELECT m.id, m.data, m.time_created, p.data FROM
              (SELECT id, data, time_created FROM message WHERE session_id = ? ORDER BY time_created DESC, id DESC LIMIT ?) m
            LEFT JOIN part p ON p.message_id = m.id
            ORDER BY m.time_created, m.id, p.id
            """
        var out: [Message] = [], current: (id: String, data: [String: Any], created: Date, parts: [[String: Any]])?
        func flush() { if let c = current { out.append(Message(data: c.data, parts: c.parts, created: c.created)) } }
        _ = rows(sql, bind: [.text(session), .int(Int64(last))]) { st -> Int in
            let id = Self.text(st, 0)
            if current?.id != id {
                flush()
                current = (id, Self.json(Self.text(st, 1)), Date(timeIntervalSince1970: Double(sqlite3_column_int64(st, 2)) / 1000), [])
            }
            if sqlite3_column_type(st, 3) != SQLITE_NULL { current?.parts.append(Self.json(Self.text(st, 3))) }
            return 0
        }
        flush()
        return out
    }

    private enum Value { case int(Int64), text(String) }
    private func rows<T>(_ sql: String, bind: [Value], _ row: (OpaquePointer) -> T) -> [T] {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK, let st else { return [] }
        defer { sqlite3_finalize(st) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, v) in bind.enumerated() {
            switch v {
            case .int(let n): sqlite3_bind_int64(st, Int32(i + 1), n)
            case .text(let s): sqlite3_bind_text(st, Int32(i + 1), s, -1, transient)
            }
        }
        var out: [T] = []
        while sqlite3_step(st) == SQLITE_ROW { out.append(row(st)) }
        return out
    }
    private static func text(_ st: OpaquePointer, _ i: Int32) -> String { sqlite3_column_text(st, i).map { String(cString: $0) } ?? "" }
    private static func json(_ s: String) -> [String: Any] { (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any] ?? [:] }
}

/// Reads OpenCode messages into what Perch knows about a session. A message is your prompt or one step of the agent's
/// turn; its parts are the text, the tool calls (with their state) and the reasoning.
public enum OpenCodeTranscript {
    /// A session nobody wrote in keeps a placeholder title, "New session - 2026-10-10T15:23:32.978Z".
    public static func isPlaceholder(_ title: String) -> Bool { title.isEmpty || title.hasPrefix("New session - ") || title.hasPrefix("Child session - ") }

    public static func digest(_ messages: [OpenCodeStore.Message]) -> SessionDigest {
        var d = SessionDigest()
        var open: [(id: String, tool: PendingTool)] = []
        for m in messages {
            let role = m.data["role"] as? String
            let time = m.data["time"] as? [String: Any]
            let texts = m.parts.filter { $0["type"] as? String == "text" && $0["synthetic"] as? Bool != true && $0["ignored"] as? Bool != true }
                .compactMap { $0["text"] as? String }
            let full = texts.joined(separator: "\n\n")
            let line = TranscriptParser.text(from: texts.joined(separator: " "))
            if role == "user" {
                guard let line, !line.isEmpty else { continue }
                d.turnOpen = true; d.interrupted = false; d.stoppedAt = nil; d.failed = nil; open = []
                d.lastUserText = line; if !Recap.isAcknowledgement(line) { d.lastAsk = line }; d.narration = nil; d.step = nil; d.work = Work()
                d.lastTimestamp = m.created; d.lastRole = "user"
                d.recent.append(.init(role: "user", text: Recap.clip(line, 420)))
            } else if role == "assistant" {
                for p in m.parts where p["type"] as? String == "tool" {
                    let name = p["tool"] as? String ?? "tool", state = p["state"] as? [String: Any] ?? [:]
                    let input = state["input"] as? [String: Any] ?? [:]
                    d.didWork = true
                    if let step = Activity.step(tool: name, input: input) { d.step = step }; d.work.note(tool: name, input: input)
                    let id = p["callID"] as? String ?? UUID().uuidString
                    if ["pending", "running"].contains(state["status"] as? String ?? "") { open.append((id, PendingTool(block: ["name": name, "input": input]))) }
                    else { open.removeAll { $0.id == id } }
                }
                // Still streaming, or a step that ended in tool calls (another step follows): the turn goes on.
                let completed = time?["completed"] != nil, finish = m.data["finish"] as? String
                d.turnOpen = !completed || finish == "tool-calls"
                if let e = m.data["error"] as? [String: Any] {
                    d.turnOpen = false; open = []
                    let at = (time?["completed"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) } ?? m.created
                    if e["name"] as? String == "MessageAbortedError" { d.interrupted = true; d.stoppedAt = at }
                    else { d.failed = ((e["data"] as? [String: Any])?["message"] as? String) ?? (e["name"] as? String) ?? "error" }
                }
                guard let line, !line.isEmpty else { continue }
                d.lastAssistantText = line; d.lastAssistantFull = TranscriptParser.text(from: full, keepLines: true); d.narration = line
                d.lastTimestamp = m.created; d.lastRole = "assistant"
                d.recent.append(.init(role: "assistant", text: Recap.clip(line, 420)))
            }
            if d.recent.count > 12 { d.recent.removeFirst() }
        }
        d.pendingTool = d.turnOpen ? open.last?.tool : nil
        return d
    }
}
