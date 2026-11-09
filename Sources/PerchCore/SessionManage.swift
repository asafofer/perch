import Foundation

/// What Perch can do to a session beyond opening it: rename it, archive it, delete it. Each agent keeps its sessions its own
/// way, so each has its own route (`docs/behavior/manage.md`); what a session offers is what its route can do.
public enum ManageAction: String, Sendable, CaseIterable {
    case rename, archive, delete
}

public enum SessionManage {
    /// What the card's More menu offers for a session, in the menu's order. Nothing when Perch has no safe route:
    /// Cursor (its chats sit in a file the app holds open), Claude tasks and chats (not tried yet), Conductor workspaces
    /// (their own list would not follow), and sample data. A terminal session still running is not deleted from under its agent.
    public static func actions(for p: Project) -> [ManageAction] {
        guard p.sessionId != nil, p.conductor == nil else { return [] }
        let running = p.pid != nil || p.status.kind == "running"
        switch p.app {
        case Agent.claude.id:
            if p.desktopSessionId != nil { return [.rename, .archive, .delete] }   // the Claude app, through its own sidebar menu
            return p.terminal ? (running ? [.rename] : [.rename, .delete]) : []   // a terminal has no archive of its own
        case Agent.codex.id, Agent.opencode.id: return running ? [.rename] : [.rename, .archive, .delete]
        case Agent.pi.id: return running ? [.rename] : [.rename, .delete]
        default: return []
        }
    }

    /// A line the menu shows under the choices when the route has a cost the person should know about.
    public static func note(for p: Project) -> String? {
        p.app == Agent.claude.id && p.desktopSessionId != nil ? "Brings Claude forward" : nil
    }

    /// The same session under a name you just gave it, until the next scan reads it from the agent: the title is `topic`, or the
    /// name when it has none (a chat started with no project).
    public static func retitled(_ p: Project, _ title: String) -> Project {
        var q = p
        if p.topic.isEmpty { q.name = title } else { q.topic = title }
        return q
    }

    // MARK: Claude Code in a terminal

    /// The title record Claude Code writes for /rename: the last one wins, as Perch reads it.
    public static func claudeTitleLine(sessionId: String, title: String) -> String {
        json(["type": "custom-title", "customTitle": title, "sessionId": sessionId])
    }

    // MARK: pi

    /// pi's own name record (what /name writes): an entry in the tree, hung under the last one.
    public static func piNameLine(name: String, parentId: String?, at: Date = Date(), id: String = String(UUID().uuidString.prefix(8)).lowercased()) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var o: [String: Any] = ["type": "session_info", "id": id, "timestamp": f.string(from: at), "name": name]
        o["parentId"] = parentId ?? NSNull()
        return json(o)
    }

    // MARK: Codex

    /// What `codex app-server` is told over its standard input, one JSON line each: the handshake, then the request (id 2).
    public enum CodexRPC {
        public static let handshake = [
            json(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "perch", "version": "1"]]]),
            json(["method": "initialized"]),
        ]
        public static func request(_ a: ManageAction, thread: String, name: String? = nil) -> String {
            switch a {
            case .rename: json(["id": 2, "method": "thread/name/set", "params": ["threadId": thread, "name": name ?? ""]])
            case .archive: json(["id": 2, "method": "thread/archive", "params": ["threadId": thread]])
            case .delete: json(["id": 2, "method": "thread/delete", "params": ["threadId": thread]])
            }
        }
        /// What a reply line says about the request: nil while it is some other line, then whether it worked (and why not).
        public static func outcome(of line: String) -> (ok: Bool, why: String)? {
            guard let o = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any], (o["id"] as? Int) == 2 else { return nil }
            if let e = o["error"] as? [String: Any] { return (false, e["message"] as? String ?? "Codex refused") }
            return (true, "")
        }
    }

    // MARK: OpenCode

    /// What `opencode serve` is asked over HTTP.
    public struct OpenCodeCall: Equatable, Sendable {
        public let method: String, path: String, body: String?
    }
    public static func openCodeCall(_ a: ManageAction, session: String, name: String? = nil, now: Date = Date()) -> OpenCodeCall {
        let path = "/session/" + (session.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? session)
        switch a {
        case .rename: return OpenCodeCall(method: "PATCH", path: path, body: json(["title": name ?? ""]))
        case .archive: return OpenCodeCall(method: "PATCH", path: path, body: json(["time": ["archived": Int(now.timeIntervalSince1970 * 1000)]]))
        case .delete: return OpenCodeCall(method: "DELETE", path: path, body: nil)
        }
    }

    // MARK: Files

    /// Claude Code's transcript for a session: ~/.claude/projects/<folder>/<id>.jsonl.
    public static func claudeTranscript(home: URL, sessionId: String) -> URL? {
        find(in: home.appendingPathComponent(".claude/projects"), file: { $0 == sessionId + ".jsonl" })
    }
    /// pi's session file: ~/.pi/agent/sessions/<folder>/<time>_<id>.jsonl.
    public static func piSession(home: URL, sessionId: String) -> URL? {
        find(in: home.appendingPathComponent(".pi/agent/sessions"), file: { $0.hasSuffix("_" + sessionId + ".jsonl") })
    }
    private static func find(in root: URL, file match: (String) -> Bool) -> URL? {
        let fm = FileManager.default
        for dir in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            if let hit = (try? fm.contentsOfDirectory(atPath: dir.path))?.first(where: match) { return dir.appendingPathComponent(hit) }
        }
        return nil
    }

    /// Adds a line to the end of a session file, on a line of its own even when the file did not end with a newline.
    public static func append(line: String, to url: URL) throws {
        let h = try FileHandle(forUpdating: url)
        defer { try? h.close() }
        let end = try h.seekToEnd()
        var prefix = ""
        if end > 0 {
            try h.seek(toOffset: end - 1)
            if try h.read(upToCount: 1) != Data("\n".utf8) { prefix = "\n" }
            try h.seekToEnd()
        }
        try h.write(contentsOf: Data((prefix + line + "\n").utf8))
    }

    /// The id of the last entry in a pi session file: the one a new entry hangs under.
    public static func lastEntryId(in url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        try? h.seek(toOffset: size > 65_536 ? size - 65_536 : 0)
        let text = String(decoding: (try? h.readToEnd()) ?? Data(), as: UTF8.self)
        for line in text.split(separator: "\n").reversed() {
            if let o = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any], let id = o["id"] as? String { return id }
        }
        return nil
    }

    static func json(_ o: [String: Any]) -> String {
        String(decoding: (try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data(), as: UTF8.self)
    }
}
