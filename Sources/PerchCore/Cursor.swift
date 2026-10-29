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
        /// Cursor is waiting on you: a command, a search or an edit that needs your OK.
        public let blocking: Bool
        /// When the chat last changed, as Cursor says. A call waiting on you writes nothing to the transcript, so the file's age
        /// alone would call a chat that has waited since you sent your prompt old.
        public let updated: Date?
    }
    /// The call a chat waits on, as Cursor names it (`run_terminal_command_v2`, `web_search`) with its arguments.
    public struct Pending: Equatable, Sendable {
        public let name: String
        public let params: [String: String]
        public static func == (a: Pending, b: Pending) -> Bool { a.name == b.name && a.params == b.params }
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
        query("SELECT workspaceId, isArchived, isSubagent, value, lastUpdatedAt FROM composerHeaders WHERE composerId = ?", id) { st in
            let o = Self.text(st, 3).flatMap { (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any] }
            var ms = Double(sqlite3_column_int64(st, 4))
            if ms == 0 { ms = (o?["lastUpdatedAt"] as? Double) ?? 0 }
            out = Header(workspaceId: Self.text(st, 0), archived: sqlite3_column_int(st, 1) != 0, subagent: sqlite3_column_int(st, 2) != 0,
                         blocking: o?["hasBlockingPendingActions"] as? Bool ?? false, updated: ms > 0 ? Date(timeIntervalSince1970: ms / 1000) : nil)
        }
        return out
    }

    /// The call a chat is waiting on you for: its newest tool call that has not finished. Only the chat's last few messages
    /// are read, each by its key, and only the fields wanted.
    public func pending(_ id: String) -> Pending? {
        var bubbles: [String] = []
        query("SELECT json_extract(CAST(value AS TEXT), '$.fullConversationHeadersOnly') FROM cursorDiskKV WHERE key = ?", "composerData:" + id) { st in
            guard let json = Self.text(st, 0), let list = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [[String: Any]] else { return }
            bubbles = list.suffix(8).compactMap { $0["bubbleId"] as? String }
        }
        for bubble in bubbles.reversed() {
            var hit: Pending?
            query("""
                SELECT json_extract(v, '$.toolFormerData.status'), json_extract(v, '$.toolFormerData.name'), json_extract(v, '$.toolFormerData.params')
                FROM (SELECT CAST(value AS TEXT) AS v FROM cursorDiskKV WHERE key = ?)
                """, "bubbleId:\(id):\(bubble)") { st in
                guard Self.text(st, 0) == "loading", let name = Self.text(st, 1) else { return }
                let params = ((Self.text(st, 2)).flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) } as? [String: Any]) ?? [:]
                hit = Pending(name: name, params: params.compactMapValues { $0 as? String })
            }
            if let hit { return hit }
        }
        return nil
    }

    /// The id of the chat Cursor's Agents window shows (`cursor/glass.selectedAgent`), as Cursor last saved it. It is what names
    /// a chat for certain: two chats can share a title.
    public func selectedChat() -> String? {
        var out: String?
        query("SELECT CAST(value AS TEXT) FROM ItemTable WHERE key = ?", "cursor/glass.selectedAgent") { st in out = Self.text(st, 0) }
        return out
    }

    /// The title and folder of a chat, from its `composerData` row. The row can be large (it carries every file the chat
    /// touched), so this is asked for only when the transcript changed.
    public func chat(_ id: String) -> Chat? {
        var out: Chat?
        // Only the three fields wanted leave SQLite: the row also holds the chat's encryption keys.
        query("""
            SELECT json_extract(v, '$.name'), json_extract(v, '$.workspaceIdentifier.id'), json_extract(v, '$.hasUnreadMessages')
            FROM (SELECT CAST(value AS TEXT) AS v FROM cursorDiskKV WHERE key = ?)
            """, "composerData:" + id) { st in
            let name = Self.text(st, 0)?.trimmingCharacters(in: .whitespacesAndNewlines)
            out = Chat(name: name?.isEmpty == false ? name : nil, workspaceId: Self.text(st, 1), unread: sqlite3_column_int(st, 2) != 0)
        }
        return out
    }

    /// An agent that runs in Cursor's cloud, as the list Cursor last fetched has it (`cloudAgentRepository.agents.<user>` in
    /// `ItemTable`). What it said is not kept on this Mac: only the title, repository, times and state.
    public struct CloudAgent: Equatable, Sendable {
        public enum State: Sendable { case running, awaiting, done, failed }
        public let id: String
        public let name: String?
        /// `github.com/owner/repo`, as Cursor writes it.
        public let repo: String?
        public let branch: String?
        public let state: State
        public let unread: Bool
        public let created: Date?
        public let updated: Date
        public let prUrl: String?
    }

    /// The cloud agents of the signed-in account, newest first. Only the fields wanted leave SQLite. Archived, killed and
    /// expired ones, other team members', and ones that failed before they started are left out.
    public func cloudAgents() -> [CloudAgent] {
        var out: [CloudAgent] = []
        var st: OpaquePointer?
        let sql = """
            SELECT json_extract(j.value, '$.bcId'), json_extract(j.value, '$.name'), json_extract(j.value, '$.repoUrl'),
                   json_extract(j.value, '$.branchName'), json_extract(j.value, '$.status'), json_extract(j.value, '$.workflowStatus'),
                   json_extract(j.value, '$.isUnread'), json_extract(j.value, '$.hasPendingInteraction'),
                   json_extract(j.value, '$.isArchived') OR json_extract(j.value, '$.isKilled') OR json_extract(j.value, '$.isOwnedByDifferentTeamMember'),
                   json_extract(j.value, '$.hasStartedVm'), json_extract(j.value, '$.createdAt'),
                   max(COALESCE(json_extract(j.value, '$.updatedAt'), 0), COALESCE(json_extract(j.value, '$.lastMessageActivityAtMs'), 0)),
                   json_extract(j.value, '$.prUrl')
            FROM ItemTable t, json_each(CAST(t.value AS TEXT)) j WHERE t.key LIKE 'cloudAgentRepository.agents.%' AND json_valid(CAST(t.value AS TEXT))
            """
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK, let st else { return [] }
        defer { sqlite3_finalize(st) }
        while sqlite3_step(st) == SQLITE_ROW {
            guard let id = Self.text(st, 0), sqlite3_column_int(st, 8) == 0 else { continue }
            let status = Int(sqlite3_column_int(st, 4)), workflow = Int(sqlite3_column_int(st, 5))
            // CloudAgentWorkflowStatus: 1 running, 2 idle, 3 error, 4 archived, 5 expired, 6 not yet started, 7 waiting for background
            // work. BackgroundComposerStatus (older): 1 running, 2 finished, 3 error, 4 creating, 5 expired.
            if workflow == 4 || workflow == 5 || workflow == 0 && status == 5 { continue }
            let started = sqlite3_column_int(st, 9) != 0
            var state: CloudAgent.State
            switch workflow {
            case 1, 6, 7: state = .running
            case 3: state = .failed
            case 2: state = .done
            default: state = status == 1 || status == 4 ? .running : status == 3 ? .failed : .done
            }
            if state == .failed && !started { continue }
            if sqlite3_column_int(st, 7) != 0 { state = .awaiting }
            let ms = sqlite3_column_double(st, 11)
            guard ms > 0 else { continue }
            let created = sqlite3_column_double(st, 10)
            let name = Self.text(st, 1)?.trimmingCharacters(in: .whitespacesAndNewlines)
            out.append(CloudAgent(id: id, name: name?.isEmpty == false ? name : nil, repo: Self.text(st, 2), branch: Self.text(st, 3), state: state,
                                  unread: sqlite3_column_int(st, 6) != 0, created: created > 0 ? Date(timeIntervalSince1970: created / 1000) : nil,
                                  updated: Date(timeIntervalSince1970: ms / 1000), prUrl: Self.text(st, 12)))
        }
        return out.sorted { $0.updated > $1.updated }
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
    /// Cursor's Application Support folder for the signed-in profile.
    public static var userDirectory: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Cursor/User") }

    /// What a call Cursor waits on is, in the names the card knows (a command is "Bash", a search "WebSearch").
    public static func ask(_ p: CursorStore.Pending) -> (tool: String, input: [String: Any]) {
        let q = p.params
        switch p.name {
        case "run_terminal_command_v2", "run_terminal_command": return ("Bash", ["command": q["command"] ?? ""])
        case "web_search": return ("WebSearch", ["query": q["searchTerm"] ?? q["query"] ?? ""])
        case "web_fetch", "fetch_url": return ("WebFetch", ["url": q["url"] ?? ""])
        case "edit_file_v2", "edit_file", "apply_patch": return ("Edit", ["file_path": q["relativeWorkspacePath"] ?? q["targetFile"] ?? q["path"] ?? ""])
        case "delete_file": return ("Write", ["file_path": q["targetFile"] ?? q["path"] ?? ""])
        case "read_file_v2", "read_file": return ("read", ["file_path": q["targetFile"] ?? q["path"] ?? ""])
        case "call_mcp_tool", "mcp": return ("mcp__\(q["server"] ?? "mcp")__\(q["toolName"] ?? q["name"] ?? "tool")", [:])
        default: return (p.name, [:])
        }
    }
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
