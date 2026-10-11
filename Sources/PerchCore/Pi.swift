import Foundation

/// Reads pi session files (~/.pi/agent/sessions/--<folder>--/<time>_<id>.jsonl). The first line holds the id and the folder;
/// after it come entries that form a tree (`id`, `parentId`). New entries are always appended, so the end of the file is
/// where the session is now, even after you went back to an earlier point with /tree.
public enum PiTranscript {
    public static func digest(lines: [String]) -> SessionDigest {
        var d = SessionDigest()
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        var open: [(id: String, tool: PendingTool)] = []
        for line in lines {
            guard let o = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { continue }
            let type = o["type"] as? String
            let at = (o["timestamp"] as? String).flatMap { iso.date(from: $0) ?? isoPlain.date(from: $0) }
            if type == "session" {
                d.sessionId = o["id"] as? String; d.cwd = o["cwd"] as? String; d.startedAt = at
                continue
            }
            // A name you gave it with /name; cleared when the name is removed.
            if type == "session_info" { let n = (o["name"] as? String)?.trimmingCharacters(in: .whitespaces); d.title = n?.isEmpty == false ? n : nil; continue }
            guard type == "message", let m = o["message"] as? [String: Any], let role = m["role"] as? String else { continue }
            switch role {
            case "user":
                guard let text = TranscriptParser.text(from: m["content"]), !text.isEmpty else { continue }
                d.turnOpen = true; d.interrupted = false; d.stoppedAt = nil; d.failed = nil; open = []
                d.lastUserText = text; d.lastUserFull = TranscriptParser.text(from: m["content"], keepLines: true); if !Recap.isAcknowledgement(text) { d.lastAsk = text }; d.narration = nil; d.step = nil; d.work = Work()
                d.lastTimestamp = at ?? d.lastTimestamp; d.lastRole = "user"
                d.recent.append(.init(role: "user", text: Recap.clip(text, 420)))
            case "assistant":
                let blocks = m["content"] as? [[String: Any]] ?? []
                for b in blocks where b["type"] as? String == "toolCall" {
                    let name = b["name"] as? String ?? "tool", args = b["arguments"] as? [String: Any] ?? [:]
                    d.didWork = true
                    if let step = Activity.step(tool: name, input: args) { d.step = step }; d.work.note(tool: name, input: args)
                    open.append((b["id"] as? String ?? "", PendingTool(block: ["name": name, "input": args])))
                }
                switch m["stopReason"] as? String {
                case "toolUse": d.turnOpen = true
                case "aborted": d.turnOpen = false; d.interrupted = true; d.stoppedAt = at; open = []
                case "error": d.turnOpen = false; d.failed = (m["errorMessage"] as? String) ?? "error"; open = []
                default: d.turnOpen = false; open = []
                }
                let texts = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }
                guard let text = TranscriptParser.text(from: texts.joined(separator: " ")), !text.isEmpty else { continue }
                d.lastAssistantText = text; d.lastAssistantFull = TranscriptParser.text(from: texts.joined(separator: "\n\n"), keepLines: true); d.narration = text
                d.lastTimestamp = at ?? d.lastTimestamp; d.lastRole = "assistant"
                d.recent.append(.init(role: "assistant", text: Recap.clip(text, 420)))
            case "toolResult":
                let id = m["toolCallId"] as? String ?? ""
                open.removeAll { $0.id == id }
            default: continue   // system prompts, extension messages
            }
            if d.recent.count > 12 { d.recent.removeFirst() }
        }
        d.pendingTool = d.turnOpen ? open.last?.tool : nil
        return d
    }

    /// The first thing you asked, which names a session pi lists without a name. It sits near the top of the file.
    static func firstPrompt(in url: URL, window: Int = 512_000) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard var data = try? handle.read(upToCount: window) else { return nil }
        if let last = data.lastIndex(of: 0x0A) { data = data[..<last] }   // a whole number of lines
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") where line.contains(#""role":"user""#) {
            guard let o = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  let m = o["message"] as? [String: Any], let t = TranscriptParser.text(from: m["content"]), !t.isEmpty else { continue }
            return t
        }
        return nil
    }
}
