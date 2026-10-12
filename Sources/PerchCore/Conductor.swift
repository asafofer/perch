import Foundation
import SQLite3

/// Conductor (conductor.build) runs Claude Code and Codex in a git worktree per workspace and keeps its own list of them in
/// one SQLite database. The sessions themselves are ordinary Claude Code and Codex transcripts: this maps each one's id to
/// its workspace, so a row can say where it lives and Pick up can open it there. Perch opens the database read-only.
public final class ConductorSessions: @unchecked Sendable {
    public struct Entry: Equatable, Sendable {
        /// Conductor's id for the workspace the session lives in. Its sidebar link ends in `/workspace/<id>`.
        public let workspaceId: String
        /// "claude" or "codex": the agent that runs the session.
        public let agent: String
        public let title: String?
        /// The workspace's own folder, a worktree.
        public let cwd: String
        /// The project the workspace belongs to.
        public let repo: String?
        public let branch: String?
        /// Archived workspaces and hidden sessions stay in the database; they are not something to go back to.
        public let archived: Bool
    }
    public static let shared = ConductorSessions(database: FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/com.conductor.app/conductor.db"))
    let database: URL
    /// What was read, until the database or its write-ahead log changes: a busy session triggers a scan every half second.
    private var cache: (stamp: [Date], index: [String: Entry])?
    private let lock = NSLock()

    public init(database: URL) { self.database = database }

    /// Keys are the transcript ids: Claude Code's session id, or the Codex thread id (Conductor calls both claude_session_id).
    public func index() -> [String: Entry] {
        let stamp = [database.path, database.path + "-wal"].compactMap { SessionScanner.mtime(URL(fileURLWithPath: $0)) }
        lock.lock(); defer { lock.unlock() }
        if let cache, !stamp.isEmpty, cache.stamp == stamp { return cache.index }
        let fresh = read()
        cache = (stamp, fresh)
        return fresh
    }

    private func read() -> [String: Entry] {
        var db: OpaquePointer?
        guard FileManager.default.fileExists(atPath: database.path),
              sqlite3_open_v2(database.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { sqlite3_close(db); return [:] }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 250)
        // A newer Conductor may drop or rename a column: the plain query still finds every session, just without the
        // hidden and archived flags.
        let from = """
            FROM sessions s JOIN workspaces w ON w.id = s.workspace_id LEFT JOIN repos r ON r.id = w.repository_id
            WHERE s.claude_session_id IS NOT NULL AND w.workspace_path IS NOT NULL
            """
        var rows = query(db, "SELECT s.claude_session_id, s.agent_type, s.title, w.id, w.workspace_path, r.name, w.branch, w.state, s.is_hidden, s.remote_archived_at \(from)")
        if rows == nil { rows = query(db, "SELECT s.claude_session_id, s.agent_type, s.title, w.id, w.workspace_path, r.name, w.branch, w.state, NULL, NULL \(from)") }
        var out: [String: Entry] = [:]
        for r in rows ?? [] { out[r.id] = r.entry }
        return out
    }

    private func query(_ db: OpaquePointer?, _ sql: String) -> [(id: String, entry: Entry)]? {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK, let st else { return nil }
        defer { sqlite3_finalize(st) }
        func text(_ i: Int32) -> String? { sqlite3_column_text(st, i).map { String(cString: $0) } }
        var out: [(String, Entry)] = []
        while sqlite3_step(st) == SQLITE_ROW {
            // Conductor runs other agents too (Cursor); Perch reads only the two it knows.
            guard let id = text(0), let agent = text(1), ["claude", "codex"].contains(agent), let workspace = text(3), let cwd = text(4) else { continue }
            let title = text(2).flatMap { $0.isEmpty || $0 == "Untitled" ? nil : $0 }
            let hidden = sqlite3_column_int(st, 8) != 0, archived = text(9) != nil
            out.append((id, Entry(workspaceId: workspace, agent: agent, title: title, cwd: cwd,
                                  repo: text(5), branch: text(6),
                                  archived: hidden || archived || (text(7) ?? "").lowercased().hasPrefix("archiv"))))
        }
        return out
    }
}
