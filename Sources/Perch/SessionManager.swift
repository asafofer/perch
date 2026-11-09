import AppKit
import PerchCore

/// Does what the card's More menu asks of a session (rename, archive, delete), each the way its agent allows
/// (`docs/behavior/manage.md`). Runs off the main thread: every route waits on a process, a server or a file.
enum SessionManager {
    struct Failure: Error { let why: String }

    static func perform(_ a: ManageAction, on p: Project, name: String?) -> Result<Void, Failure> {
        guard let id = p.sessionId else { return .failure(Failure(why: "it has no session id")) }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let r: Result<Void, Failure>
        switch p.app {
        case Agent.claude.id:
            if let desktop = p.desktopSessionId { r = ClaudeComposer.manage(a, session: desktop, titles: [p.topic, p.name].filter { !$0.isEmpty }, name: name) }
            else { r = files(a, claudeTranscript: SessionManage.claudeTranscript(home: home, sessionId: id), id: id, name: name) }
        case Agent.pi.id: r = files(a, pi: SessionManage.piSession(home: home, sessionId: id), name: name)
        case Agent.codex.id: r = codex(a, thread: id, name: name)
        case Agent.opencode.id: r = openCode(a, session: id, name: name)
        default: r = .failure(Failure(why: "Perch cannot change this kind of session"))
        }
        if case .failure(let f) = r { NSLog("Perch: \(a.rawValue) \(p.app) session failed: \(f.why)") }
        return r
    }

    // MARK: files (Claude Code and pi in a terminal)

    private static func files(_ a: ManageAction, claudeTranscript url: URL?, id: String, name: String?) -> Result<Void, Failure> {
        guard let url else { return .failure(Failure(why: "its transcript is not where Claude Code keeps it")) }
        switch a {
        case .rename:
            guard let name else { return .failure(Failure(why: "no name")) }
            return write { try SessionManage.append(line: SessionManage.claudeTitleLine(sessionId: id, title: name), to: url) }
        case .delete: return write { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
        case .archive: return .failure(Failure(why: "Claude Code has no archive"))
        }
    }
    private static func files(_ a: ManageAction, pi url: URL?, name: String?) -> Result<Void, Failure> {
        guard let url else { return .failure(Failure(why: "its session file is not where pi keeps it")) }
        switch a {
        case .rename:
            guard let name else { return .failure(Failure(why: "no name")) }
            return write { try SessionManage.append(line: SessionManage.piNameLine(name: name, parentId: SessionManage.lastEntryId(in: url)), to: url) }
        case .delete: return write { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
        case .archive: return .failure(Failure(why: "pi has no archive"))
        }
    }
    private static func write(_ body: () throws -> Void) -> Result<Void, Failure> {
        do { try body(); return .success(()) } catch { return .failure(Failure(why: error.localizedDescription)) }
    }

    // MARK: Codex (the app and the terminal share its threads)

    /// `codex app-server` over its standard input and output: the handshake, then one request, and its answer.
    private static func codex(_ a: ManageAction, thread: String, name: String?) -> Result<Void, Failure> {
        guard let bin = binary("codex") else { return .failure(Failure(why: "Perch cannot find the codex command")) }
        let proc = Process(), inp = Pipe(), out = Pipe()
        proc.executableURL = bin; proc.arguments = ["app-server"]
        proc.standardInput = inp; proc.standardOutput = out; proc.standardError = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0), lock = NSLock()
        var buffer = "", outcome: (ok: Bool, why: String)?, sent = false
        let send = { (line: String) in inp.fileHandleForWriting.write(Data((line + "\n").utf8)) }
        // Read while it runs: a pipe holds 64 KB, and Codex writes more than that.
        out.fileHandleForReading.readabilityHandler = { h in
            let chunk = String(decoding: h.availableData, as: UTF8.self)
            lock.lock(); defer { lock.unlock() }
            buffer += chunk
            while let nl = buffer.firstIndex(of: "\n") {
                let line = String(buffer[..<nl]); buffer.removeSubrange(...nl)
                if !sent, ((try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any])?["id"] as? Int == 1 { sent = true; send(SessionManage.CodexRPC.request(a, thread: thread, name: name)) }
                else if let o = SessionManage.CodexRPC.outcome(of: line) { outcome = o; done.signal() }
            }
        }
        do { try proc.run() } catch { return .failure(Failure(why: "codex would not start")) }
        defer { out.fileHandleForReading.readabilityHandler = nil; try? inp.fileHandleForWriting.close(); proc.terminate() }
        for line in SessionManage.CodexRPC.handshake { send(line) }
        guard done.wait(timeout: .now() + 12) == .success, let outcome else { return .failure(Failure(why: "Codex did not answer")) }
        return outcome.ok ? .success(()) : .failure(Failure(why: outcome.why))
    }

    // MARK: OpenCode (its terminal app and its desktop app share one database)

    /// A server of its own for the moment it takes: `opencode serve` on a free port, the call, then it is stopped.
    private static func openCode(_ a: ManageAction, session: String, name: String?) -> Result<Void, Failure> {
        guard let bin = binary("opencode") else { return .failure(Failure(why: "Perch cannot find the opencode command")) }
        guard let port = freePort() else { return .failure(Failure(why: "no free port")) }
        let proc = Process()
        proc.executableURL = bin; proc.arguments = ["serve", "--hostname", "127.0.0.1", "--port", String(port)]
        proc.standardOutput = FileHandle.nullDevice; proc.standardError = FileHandle.nullDevice; proc.standardInput = FileHandle.nullDevice
        do { try proc.run() } catch { return .failure(Failure(why: "opencode would not start")) }
        defer { proc.terminate() }
        let base = "http://127.0.0.1:\(port)"
        // Up when it answers its session list.
        var up = false
        for _ in 0..<60 {
            if let s = http("GET", base + "/session", body: nil)?.status, s < 500 { up = true; break }
            if !proc.isRunning { break }
            Thread.sleep(forTimeInterval: 0.2)
        }
        guard up else { return .failure(Failure(why: "OpenCode's server did not start")) }
        let call = SessionManage.openCodeCall(a, session: session, name: name)
        guard let r = http(call.method, base + call.path, body: call.body) else { return .failure(Failure(why: "OpenCode did not answer")) }
        return (200..<300).contains(r.status) ? .success(()) : .failure(Failure(why: "OpenCode said \(r.status)"))
    }
    private static func http(_ method: String, _ url: String, body: String?) -> (status: Int, body: Data)? {
        guard let u = URL(string: url) else { return nil }
        var req = URLRequest(url: u, timeoutInterval: 5)
        req.httpMethod = method
        if let body { req.httpBody = Data(body.utf8); req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let sem = DispatchSemaphore(value: 0)
        var result: (Int, Data)?
        URLSession.shared.dataTask(with: req) { d, r, _ in
            if let r = r as? HTTPURLResponse { result = (r.statusCode, d ?? Data()) }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 6)
        return result
    }
    private static func freePort() -> Int? {
        let s = socket(AF_INET, SOCK_STREAM, 0); guard s >= 0 else { return nil }
        defer { close(s) }
        var addr = sockaddr_in(); addr.sin_family = sa_family_t(AF_INET); addr.sin_addr.s_addr = inet_addr("127.0.0.1"); addr.sin_port = 0
        let ok = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard ok == 0 else { return nil }
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let got = withUnsafeMutablePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(s, $0, &len) } }
        return got == 0 ? Int(UInt16(bigEndian: addr.sin_port)) : nil
    }

    /// An agent's command, where its installers put it.
    private static func binary(_ name: String) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var dirs = ["/opt/homebrew/bin", "/usr/local/bin", home + "/.local/bin", home + "/.bun/bin", home + "/.opencode/bin", "/Applications/Codex.app/Contents/Resources"]
        dirs += (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for d in dirs where FileManager.default.isExecutableFile(atPath: d + "/" + name) { return URL(fileURLWithPath: d + "/" + name) }
        return nil
    }
}
