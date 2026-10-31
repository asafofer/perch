import Testing
import Foundation
@testable import PerchCore

/// A home folder with Oh My Pi session files: a 256-byte title line, then pi's header and entries.
private final class OmpHome {
    let url: URL
    let now = Date()
    init() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("perch-omp-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }

    var scanner: SessionScanner {
        let s = SessionScanner(home: url, desktop: DesktopSessions(root: url.appendingPathComponent("none")))
        s.usable = { FileManager.default.fileExists(atPath: $0) }
        s.lookUpGit = { _ in nil }; s.lookUpBranch = { _ in nil }; s.lookUpRepo = { _ in nil }
        return s
    }
    @discardableResult func folder(_ path: String) -> String {
        let u = url.appendingPathComponent(path)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u.path
    }
    func ts(_ offset: TimeInterval) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: now.addingTimeInterval(offset))
    }
    func title(_ t: String) -> String {
        let line = #"{"type":"title","v":1,"title":"\#(t)","source":"auto","pad":""#
        return line + String(repeating: " ", count: max(0, 254 - line.count - 2)) + #""}"#
    }
    @discardableResult func session(_ id: String, cwd: String, title t: String = "", ago: TimeInterval = 60, entries: [String], subagent: Bool = false) -> URL {
        let bucket = url.appendingPathComponent(".omp/agent/sessions/-" + cwd.dropFirst().replacingOccurrences(of: "/", with: "-"))
        let dir = subagent ? bucket.appendingPathComponent(id) : bucket
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let lines = [title(t), #"{"type":"session","version":3,"id":"\#(id)","timestamp":"\#(ts(-ago - 30))","cwd":"\#(cwd)"}"#] + entries
        let f = dir.appendingPathComponent("2026-10-31T13-15-12-016Z_\(id).jsonl")
        try? (lines.joined(separator: "\n") + "\n").data(using: .utf8)!.write(to: f)
        try? FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-ago)], ofItemAtPath: f.path)
        return f
    }
    func user(_ t: String, _ at: TimeInterval) -> String {
        #"{"type":"message","id":"u","parentId":null,"timestamp":"\#(ts(at))","message":{"role":"user","content":[{"type":"text","text":"\#(t)"}]}}"#
    }
    func bash(_ id: String, _ command: String, _ at: TimeInterval) -> String {
        #"{"type":"message","id":"a1","parentId":"u","timestamp":"\#(ts(at))","message":{"role":"assistant","stopReason":"toolUse","content":[{"type":"toolCall","id":"\#(id)","name":"bash","arguments":{"command":"\#(command)"}}]}}"#
    }
    func result(_ id: String, _ text: String, _ at: TimeInterval) -> String {
        #"{"type":"message","id":"r","parentId":"a1","timestamp":"\#(ts(at))","message":{"role":"toolResult","toolCallId":"\#(id)","toolName":"bash","content":[{"type":"text","text":"\#(text)"}]}}"#
    }
    func said(_ t: String, _ at: TimeInterval) -> String {
        #"{"type":"message","id":"a2","parentId":"r","timestamp":"\#(ts(at))","message":{"role":"assistant","stopReason":"stop","content":[{"type":"text","text":"\#(t)"}]}}"#
    }
}

@Suite struct OmpScanTests {
    @Test func ompSessionsAreListedByTheirTitleLineOrRename() {
        let h = OmpHome(), site = h.folder("code/lint")
        h.session("o1", cwd: site, title: "Tighten the lint rules", ago: 60, entries: [
            h.user("make the two noisy rules report the line", -90), h.bash("c1", "pnpm lint", -85), h.result("c1", "ok", -80),
            h.said("Both rules now report the exact line.", -75)])
        h.session("o2", cwd: site, ago: 120, entries: [
            h.user("add a rule for unused exports please", -150), h.bash("c1", "pnpm lint", -145), h.result("c1", "ok", -140), h.said("Added it.", -135),
            #"{"type":"title_change","id":"t","parentId":"a2","timestamp":"\#(h.ts(-130))","title":"Unused exports rule","source":"user"}"#])
        // a subagent's file, a folder deeper: no row
        h.session("sub", cwd: site, ago: 10, entries: [h.user("look at the config files carefully", -20), h.bash("c9", "ls", -15)], subagent: true)
        let found = h.scanner.omp(limit: 15, now: h.now).map(\.project)
        #expect(found.map(\.sessionId) == ["o1", "o2"])
        #expect(found.map(\.topic) == ["Tighten the lint rules", "Unused exports rule"])
        #expect(found.first?.app == "omp"); #expect(found.first?.terminal == true)
        #expect(found.first?.status.text == "Oh My Pi replied")
        #expect(found.first?.said == "Both rules now report the exact line.")
    }

    @Test func anUntitledOmpSessionGoesByItsFirstPromptAndShowsItsStep() {
        let h = OmpHome(), site = h.folder("code/lint")
        h.session("w", cwd: site, ago: 2, entries: [h.user("run the whole lint suite please", -10), h.bash("c1", "pnpm lint --fix", -5)])
        let p = h.scanner.omp(limit: 15, now: h.now).first?.project
        #expect(p?.topic == "run the whole lint suite please")
        #expect(p?.status.kind == "running"); #expect(p?.now == "Running `pnpm lint --fix`")
    }

    @Test func ompIsItsOwnAgent() {
        #expect(Agent.recognise(executable: "/opt/homebrew/Cellar/omp/18.14.1/bin/omp", argv0: "omp") == .omp)
        #expect(Agent.omp.resume("01a1", prompt: "go on") == "omp --resume 01a1 'go on'")
        #expect(NewSession.command(agent: "omp", prompt: "fix it") == "omp 'fix it'")
        // its questions are answered from the notch, its approvals in its terminal
        let q = Ask(id: "q", agent: "omp", tool: "AskUserQuestion", input: ["questions": [["question": "Which colour?", "options": [["label": "Red"], ["label": "Blue"]]]]])
        #expect(q.answerable)
        let a = Ask(id: "a", agent: "omp", tool: "bash", input: ["command": "ls"])
        #expect(!a.answerable); #expect(a.title == "Oh My Pi wants to run a command")
    }
}
