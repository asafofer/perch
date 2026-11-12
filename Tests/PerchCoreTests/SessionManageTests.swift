import Foundation
import Testing
@testable import PerchCore

@Suite struct SessionManageTests {
    private func project(app: String, id: String? = "abc", desktop: String? = nil, terminal: Bool = false, running: Bool = false, conductor: String? = nil) -> Project {
        var p = Project(id: "p", name: "n", branch: nil, away: "1m", at: "", headline: "", context: "", next: "", topic: "t", app: app,
                        agents: [AgentStatus(kind: running ? .running : .done, text: "x", app: app)], steps: [], sessionId: id, desktopSessionId: desktop)
        p.terminal = terminal; p.conductor = conductor
        return p
    }

    @Test func eachSourceOffersWhatItsRouteCanDo() {
        #expect(SessionManage.actions(for: project(app: "claude", desktop: "local_1")) == [.rename, .archive, .delete])
        #expect(SessionManage.actions(for: project(app: "claude", terminal: true)) == [.rename, .delete])   // no archive of its own
        #expect(SessionManage.actions(for: project(app: "codex")) == [.rename, .archive, .delete])
        #expect(SessionManage.actions(for: project(app: "opencode")) == [.rename, .archive, .delete])
        #expect(SessionManage.actions(for: project(app: "pi", terminal: true)) == [.rename, .delete])
    }

    @Test func nothingForWhatPerchCannotChangeSafely() {
        #expect(SessionManage.actions(for: project(app: "cursor")).isEmpty)
        #expect(SessionManage.actions(for: project(app: "cowork")).isEmpty)
        #expect(SessionManage.actions(for: project(app: "chat")).isEmpty)
        #expect(SessionManage.actions(for: project(app: "codex", conductor: "ws")).isEmpty)
        #expect(SessionManage.actions(for: project(app: "claude", id: nil, terminal: true)).isEmpty)   // sample data
    }

    @Test func aSessionAtWorkIsOnlyRenamed() {
        #expect(SessionManage.actions(for: project(app: "codex", running: true)) == [.rename])
        #expect(SessionManage.actions(for: project(app: "pi", terminal: true, running: true)) == [.rename])
        var live = project(app: "claude", terminal: true); live.pid = 42
        #expect(SessionManage.actions(for: live) == [.rename])
    }

    @Test func onlyTheClaudeAppSaysItComesForward() {
        #expect(SessionManage.note(for: project(app: "claude", desktop: "local_1")) == "Brings Claude forward")
        #expect(SessionManage.note(for: project(app: "claude", terminal: true)) == nil)
        #expect(SessionManage.note(for: project(app: "codex")) == nil)
    }

    @Test func claudeAndPiNameRecordsAreTheOnesPerchReads() {
        let c = SessionManage.claudeTitleLine(sessionId: "s1", title: "Say \"hi\"")
        let o = try! JSONSerialization.jsonObject(with: Data(c.utf8)) as! [String: Any]
        #expect(o["type"] as? String == "custom-title" && o["customTitle"] as? String == "Say \"hi\"" && o["sessionId"] as? String == "s1")
        var d = TranscriptParser.digest(lines: [c])
        #expect(d.title == "Say \"hi\"")
        d = PiTranscript.digest(lines: [SessionManage.piNameLine(name: "My name", parentId: "a1b2c3d4")])
        #expect(d.title == "My name")
        let pi = try! JSONSerialization.jsonObject(with: Data(SessionManage.piNameLine(name: "x", parentId: "p1").utf8)) as! [String: Any]
        #expect(pi["parentId"] as? String == "p1" && pi["type"] as? String == "session_info")
    }

    @Test func codexIsToldTheHandshakeThenTheRequest() {
        #expect(SessionManage.CodexRPC.handshake.count == 2 && SessionManage.CodexRPC.handshake[0].contains("\"initialize\""))
        let r = SessionManage.CodexRPC.request(.rename, thread: "t1", name: "New")
        #expect(r.contains("\"thread/name/set\"") && r.contains("\"threadId\":\"t1\"") && r.contains("\"name\":\"New\"") && r.contains("\"id\":2"))
        #expect(SessionManage.CodexRPC.request(.archive, thread: "t1").contains("\"thread/archive\""))
        #expect(SessionManage.CodexRPC.request(.delete, thread: "t1").contains("\"thread/delete\""))
        #expect(SessionManage.CodexRPC.outcome(of: #"{"id":1,"result":{}}"#) == nil)   // the handshake's answer is not the request's
        #expect(SessionManage.CodexRPC.outcome(of: #"{"method":"thread/archived","params":{}}"#) == nil)
        #expect(SessionManage.CodexRPC.outcome(of: #"{"id":2,"result":{}}"#)?.ok == true)
        #expect(SessionManage.CodexRPC.outcome(of: #"{"id":2,"error":{"code":-1,"message":"no such thread"}}"#)?.why == "no such thread")
    }

    @Test func openCodeIsAskedOverItsRestApi() {
        let rename = SessionManage.openCodeCall(.rename, session: "ses_1", name: "New")
        #expect(rename.method == "PATCH" && rename.path == "/session/ses_1" && rename.body == #"{"title":"New"}"#)
        let archive = SessionManage.openCodeCall(.archive, session: "ses_1", now: Date(timeIntervalSince1970: 100))
        #expect(archive.body == #"{"time":{"archived":100000}}"#)
        let delete = SessionManage.openCodeCall(.delete, session: "ses_1")
        #expect(delete.method == "DELETE" && delete.body == nil)
    }

    @Test func filesAreFoundAndAppendedOnALineOfTheirOwn() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("perch-manage-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let claude = home.appendingPathComponent(".claude/projects/-a-b"), pi = home.appendingPathComponent(".pi/agent/sessions/--a--")
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pi, withIntermediateDirectories: true)
        let cf = claude.appendingPathComponent("s1.jsonl"), pf = pi.appendingPathComponent("2026-01-01T00-00-00-000Z_s2.jsonl")
        try "{\"type\":\"user\"}".write(to: cf, atomically: true, encoding: .utf8)   // no newline at the end
        try "{\"type\":\"session\",\"id\":\"s2\"}\n{\"type\":\"message\",\"id\":\"e1\",\"parentId\":null}\n".write(to: pf, atomically: true, encoding: .utf8)
        #expect(SessionManage.claudeTranscript(home: home, sessionId: "s1")?.lastPathComponent == "s1.jsonl")
        #expect(SessionManage.claudeTranscript(home: home, sessionId: "nope") == nil)
        #expect(SessionManage.piSession(home: home, sessionId: "s2")?.lastPathComponent.hasSuffix("_s2.jsonl") == true)
        #expect(SessionManage.lastEntryId(in: pf) == "e1")

        try SessionManage.append(line: SessionManage.claudeTitleLine(sessionId: "s1", title: "T"), to: cf)
        try SessionManage.append(line: "{\"x\":1}", to: pf)
        let lines = try String(contentsOf: cf, encoding: .utf8).split(separator: "\n")
        #expect(lines.count == 2 && lines[0] == "{\"type\":\"user\"}")
        #expect(try String(contentsOf: pf, encoding: .utf8).split(separator: "\n").count == 3)
    }
}
