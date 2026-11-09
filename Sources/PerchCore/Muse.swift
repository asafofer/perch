import Foundation
import SQLite3

/// Reads Muse Code's session logs (~/.local/share/muse/sessions/YYYY/MM/DD/<id>/session.jsonl). Each line is an envelope:
/// `stream.id` (the session), `recorded_at` (microseconds), `payload_type` and `payload`. What was said is in
/// `runtime.session` records whose `payload.kind` is `run`: `event.kind` `started` (your prompt), `assistant_message_committed`
/// (its reply), `assistant_tool_calls_committed` (`tool_calls`: `name`, `args`, `call_id`), `tool_result_batch_committed`
/// (`results`: `tool_call_id`) and `terminal` (the turn's end). Everything else (tasks, reminders, diagnostics) is skipped.
/// A log is heavy (about 100 KB a turn), so only its tail is read.
public enum MuseTranscript {
    public static func digest(lines: [String]) -> SessionDigest {
        var d = SessionDigest()
        var open: [(id: String, tool: PendingTool)] = []
        for line in lines {
            // Most lines are bookkeeping: skip them before parsing.
            guard line.contains("\"runtime.session") || line.contains("\"session.end\"") else { continue }
            guard let o = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  let payload = o["payload"] as? [String: Any] else { continue }
            let at = (o["recorded_at"] as? Double).map { Date(timeIntervalSince1970: $0 / 1_000_000) }
            if d.sessionId == nil { d.sessionId = (o["stream"] as? [String: Any])?["id"] as? String }
            if o["payload_type"] as? String == "runtime.session.metadata" {
                d.cwd = (payload["record"] as? [String: Any])?["workspace_root"] as? String ?? d.cwd
                continue
            }
            guard payload["kind"] as? String == "run", let event = payload["event"] as? [String: Any] else { continue }
            switch event["kind"] as? String {
            case "started":
                guard let prompt = event["prompt"] as? String, let text = TranscriptParser.text(from: prompt), !text.isEmpty else { continue }
                d.turnOpen = true; d.interrupted = false; d.stoppedAt = nil; d.failed = nil; open = []
                d.lastUserText = text; d.lastUserFull = TranscriptParser.text(from: prompt, keepLines: true); if !Recap.isAcknowledgement(text) { d.lastAsk = text }
                d.narration = nil; d.step = nil; d.work = Work(); d.turnFull = nil
                d.lastTimestamp = at ?? d.lastTimestamp; d.lastRole = "user"
                d.recent.append(.init(role: "user", text: Recap.clip(text, 420)))
            case "assistant_tool_calls_committed":
                for call in event["tool_calls"] as? [[String: Any]] ?? [] {
                    let name = call["name"] as? String ?? "tool", args = arguments(call["args"])
                    d.didWork = true
                    if let step = Activity.step(tool: name, input: args) { d.step = step }; d.work.note(tool: name, input: args)
                    open.append(((call["call_id"] ?? call["id"]) as? String ?? "", PendingTool(block: ["name": name, "input": args])))
                }
                d.lastTimestamp = at ?? d.lastTimestamp
            case "tool_result_batch_committed":
                for r in event["results"] as? [[String: Any]] ?? [] {
                    let id = (r["tool_call_id"] ?? r["call_id"]) as? String ?? ""
                    open.removeAll { $0.id == id }
                }
            case "assistant_message_committed":
                guard let raw = event["text"] as? String, let text = TranscriptParser.text(from: raw), !text.isEmpty else { continue }
                d.lastAssistantText = text; d.lastAssistantFull = TranscriptParser.text(from: raw, keepLines: true); d.narration = text
                d.turnFull = TranscriptParser.joined(d.turnFull, d.lastAssistantFull)
                d.lastTimestamp = at ?? d.lastTimestamp; d.lastRole = "assistant"
                d.recent.append(.init(role: "assistant", text: Recap.clip(text, 420)))
            case "terminal":
                d.turnOpen = false; open = []
                // Muse's `TurnTerminal` (its schema, `muse schema generate-ts`): completed, failed or cancelled. The set is open:
                // its spec reads an unknown one as a plain end, so only `failed` says it went wrong.
                switch event["terminal"] as? String {
                case "cancelled": d.interrupted = true; d.stoppedAt = at
                case "failed": d.failed = (event["reason"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "error"
                default: break
                }
            default: continue
            }
            if d.recent.count > 12 { d.recent.removeFirst() }
        }
        d.pendingTool = d.turnOpen ? open.last?.tool : nil
        return d
    }

    /// A call's arguments: an object, or the same as a JSON string.
    static func arguments(_ v: Any?) -> [String: Any] {
        if let o = v as? [String: Any] { return o }
        if let s = v as? String, let o = (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any] { return o }
        return [:]
    }

    /// What the top of a log says once: the session's folder, your first prompt, and whether it ran in the terminal (only the
    /// interactive app records its start-up phases; `muse exec` runs do not, and get no row).
    public struct Head: Equatable, Sendable {
        public var cwd: String?
        public var firstPrompt: String?
        public var interactive = false
    }

    public static func head(of url: URL, window: Int = 1_000_000) -> Head? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard var data = try? handle.read(upToCount: window) else { return nil }
        if let last = data.lastIndex(of: 0x0A) { data = data[..<last] }   // a whole number of lines
        var h = Head()
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            if line.contains("\"session.startup_phases.observed\"") { h.interactive = true; continue }
            let meta = line.contains("\"runtime.session.metadata\""), prompt = h.firstPrompt == nil && line.contains("\"prompt\"") && line.contains("\"started\"")
            guard meta || prompt, let o = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  let payload = o["payload"] as? [String: Any] else { continue }
            if meta { h.cwd = (payload["record"] as? [String: Any])?["workspace_root"] as? String; continue }
            if payload["kind"] as? String == "run", let e = payload["event"] as? [String: Any], e["kind"] as? String == "started",
               let p = (e["prompt"] as? String).flatMap({ TranscriptParser.text(from: $0) }), !p.isEmpty { h.firstPrompt = p }
        }
        return h.cwd == nil ? nil : h
    }
}

/// Muse's own list of sessions (`session-index.db`, SQLite): the title Muse made for each, by session id. Read-only, and
/// only a nicety: when it cannot be opened (Muse holds it between writes), a session goes by your first prompt.
public final class MuseIndex: @unchecked Sendable {
    let url: URL
    public init(url: URL) { self.url = url }

    public func titles() -> [String: String] {
        var db: OpaquePointer?
        guard FileManager.default.fileExists(atPath: url.path),
              sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { sqlite3_close(db); return [:] }
        defer { sqlite3_close(db) }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT session_id, coalesce(nullif(effective_long_title, ''), title) FROM sessions", -1, &st, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(st) }
        var out: [String: String] = [:]
        while sqlite3_step(st) == SQLITE_ROW {
            guard let id = sqlite3_column_text(st, 0), let t = sqlite3_column_text(st, 1) else { continue }
            let title = String(cString: t).trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty { out[String(cString: id)] = title }
        }
        return out
    }
}
