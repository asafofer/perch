import Foundation
import PerchCore

/// Listens on a Unix socket for what Claude Code and Codex hooks post (see HookInstaller), one small HTTP request each.
/// Status events are answered at once. A request Perch can answer from the notch is held open until you choose,
/// it is settled elsewhere, or the hook goes away; whichever happens first.
final class HookServer: @unchecked Sendable {
    var onEvent: (@MainActor (HookEvent) -> Void)?
    /// A held request's hook went away: answered in the app, or the session ended.
    var onAbandoned: (@MainActor (String) -> Void)?

    private let queue = DispatchQueue(label: "perch.hooks")
    private var listener: DispatchSourceRead?
    private var held: [String: (fd: Int32, watch: DispatchSourceRead)] = [:]

    func start() {
        let path = HookInstaller.socket.path
        try? FileManager.default.createDirectory(at: HookInstaller.dir, withIntermediateDirectories: true)
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { NSLog("Perch: hook socket failed"); return }
        var addr = sockaddr_un(); addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8.prefix(MemoryLayout.size(ofValue: addr.sun_path) - 1)) + [0]
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes) }
        let ok = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard ok == 0, listen(fd, 32) == 0 else { NSLog("Perch: hook socket bind failed: \(errno)"); close(fd); return }
        chmod(path, 0o600)   // only you can talk to it
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        src.setEventHandler { [weak self] in
            let c = accept(fd, nil, nil)
            if c >= 0 { self?.handle(c) }
        }
        src.resume()
        listener = src
    }

    /// Answers a held request. An empty body means "no decision": the app's own prompt decides.
    func answer(_ askId: String, with body: Data) {
        queue.async { [weak self] in
            guard let self, let h = self.held.removeValue(forKey: askId) else { return }
            h.watch.cancel()
            Self.respond(h.fd, body)
        }
    }
    func release(_ askId: String) { answer(askId, with: Data()) }

    private func handle(_ c: Int32) {
        var one: Int32 = 1
        setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        var tv = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        guard let (path, body) = Self.readRequest(c) else { close(c); return }
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count == 2, ["claude", "codex"].contains(parts[0]) else { Self.respond(c, Data()); return }
        let id = UUID().uuidString
        guard let event = HookEvent.parse(agent: parts[0], event: parts[1], body: body, requestId: id) else { Self.respond(c, Data()); return }
        // Only the Claude app runs this hook alongside its own prompt. Anywhere else (a terminal, `claude -p`) the
        // prompt waits for the hook, so holding it would freeze the session: those are answered at once, with no decision.
        if case .asks(let ask) = event.kind, ask.answerable, DesktopSessions.shared.index()[event.sessionId] != nil {
            // Hold the hook open. If it goes away first (the app answered, the session ended), say so.
            let watch = DispatchSource.makeReadSource(fileDescriptor: c, queue: queue)
            watch.setEventHandler { [weak self] in
                guard let self, self.held[id] != nil else { return }
                var b: UInt8 = 0
                if recv(c, &b, 1, MSG_PEEK) <= 0 {
                    self.held[id]?.watch.cancel(); self.held[id] = nil; close(c)
                    DispatchQueue.main.async { MainActor.assumeIsolated { self.onAbandoned?(id) } }
                }
            }
            held[id] = (c, watch)
            watch.resume()
        } else {
            Self.respond(c, Data())
        }
        DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.onEvent?(event) } }
    }

    /// Request line and body of a small HTTP POST. Nil when it is not one.
    private static func readRequest(_ c: Int32) -> (String, Data)? {
        var data = Data(), buf = [UInt8](repeating: 0, count: 65_536)
        var headerEnd: Range<Data.Index>?, length = 0
        while true {
            let n = recv(c, &buf, buf.count, 0)
            if n <= 0 { break }
            data.append(contentsOf: buf[0..<n])
            if headerEnd == nil, let r = data.range(of: Data("\r\n\r\n".utf8)) {
                headerEnd = r
                let head = String(decoding: data[..<r.lowerBound], as: UTF8.self)
                for line in head.split(separator: "\r\n") where line.lowercased().hasPrefix("content-length:") {
                    length = Int(line.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) ?? 0
                }
            }
            if let r = headerEnd, data.count - r.upperBound >= length { break }
            if data.count > 8_000_000 { return nil }
        }
        guard let r = headerEnd else { return nil }
        let head = String(decoding: data[..<r.lowerBound], as: UTF8.self)
        let request = head.split(separator: "\r\n").first?.split(separator: " ") ?? []
        guard request.count >= 2 else { return nil }
        return (String(request[1]), Data(data[r.upperBound...].prefix(length)))
    }

    private static func respond(_ c: Int32, _ body: Data) {
        let head = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        let out = Data(head.utf8) + body
        out.withUnsafeBytes { p in var sent = 0; while sent < out.count { let n = send(c, p.baseAddress! + sent, out.count - sent, 0); if n <= 0 { break }; sent += n } }
        close(c)
    }
}

/// Installs the hook script and the config entries that run it. Perch only touches entries it wrote itself.
enum HookInstaller {
    /// PERCH_HOME points the installer at a stand-in home folder, so it can be tried without touching real config.
    static let home = ProcessInfo.processInfo.environment["PERCH_HOME"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser
    static let dir = home.appendingPathComponent(".config/perch")
    static let script = dir.appendingPathComponent("hook")
    static let socket = dir.appendingPathComponent("perch.sock")
    static let claudeSettings = home.appendingPathComponent(".claude/settings.json")
    static let codexHooks = home.appendingPathComponent(".codex/hooks.json")

    /// A request Perch can answer waits up to an hour for you; everything else is told "go on" at once.
    static let scriptBody = """
    #!/bin/sh
    # Perch: tells Perch what Claude Code or Codex is doing, so the notch knows the moment they need you.
    # Exits quietly when Perch is not running. Remove it from Perch's Settings.
    sock="$HOME/.config/perch/perch.sock"
    [ -S "$sock" ] || exit 0
    wait=5
    [ "$1" = claude ] && [ "$2" = PermissionRequest ] && wait=3600
    out=$(/usr/bin/curl -s --max-time "$wait" --unix-socket "$sock" -H 'Expect:' -H 'Content-Type: application/json' --data-binary @- "http://perch/$1/$2" 2>/dev/null) || exit 0
    [ -n "$out" ] && printf '%s\\n' "$out"
    exit 0

    """

    struct Hook { let event: String; let matcher: String?; let async: Bool; let timeout: Int }
    static let claudeHooks = [
        Hook(event: "UserPromptSubmit", matcher: nil, async: true, timeout: 10),
        Hook(event: "PostToolUse", matcher: "*", async: true, timeout: 10),
        Hook(event: "Stop", matcher: nil, async: true, timeout: 10),
        Hook(event: "StopFailure", matcher: nil, async: true, timeout: 10),
        Hook(event: "PermissionRequest", matcher: "*", async: false, timeout: 3600),
    ]
    static let codexHooks_ = [
        Hook(event: "UserPromptSubmit", matcher: nil, async: false, timeout: 5),
        Hook(event: "PostToolUse", matcher: "*", async: false, timeout: 5),
        Hook(event: "Stop", matcher: nil, async: false, timeout: 5),
        Hook(event: "PermissionRequest", matcher: "*", async: false, timeout: 5),
        Hook(event: "Interrupt", matcher: nil, async: false, timeout: 3),
    ]

    static func file(_ agent: String) -> URL { agent == "codex" ? codexHooks : claudeSettings }
    static func hooks(_ agent: String) -> [Hook] { agent == "codex" ? codexHooks_ : claudeHooks }

    static func isInstalled(_ agent: String) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: script.path),
              let root = read(file(agent)), let hooks = root["hooks"] as? [String: Any] else { return false }
        return Self.hooks(agent).allSatisfy { h in (hooks[h.event] as? [[String: Any]] ?? []).contains(where: isOurs) }
    }

    static func install(_ agent: String) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try scriptBody.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        try edit(agent) { hooks in
            for h in Self.hooks(agent) {
                let path = script.path.contains(" ") ? "\"\(script.path)\"" : script.path
                var handler: [String: Any] = ["type": "command", "command": "\(path) \(agent) \(h.event)", "timeout": h.timeout]
                if h.async { handler["async"] = true }
                var group: [String: Any] = ["hooks": [handler]]
                if let m = h.matcher { group["matcher"] = m }
                hooks[h.event] = (hooks[h.event] as? [[String: Any]] ?? []).filter { !isOurs($0) } + [group]
            }
        }
    }

    static func uninstall(_ agent: String) throws {
        try edit(agent) { hooks in
            for (event, value) in hooks {
                guard let groups = value as? [[String: Any]] else { continue }
                let kept = groups.filter { !isOurs($0) }
                hooks[event] = kept.isEmpty ? nil : kept
            }
        }
    }

    private static func isOurs(_ group: [String: Any]) -> Bool {
        (group["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String)?.contains(script.path) == true }
    }

    private static func read(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Reads the file, lets `change` edit its "hooks", and writes it back. A file that is not plain JSON is left alone.
    private static func edit(_ agent: String, _ change: (inout [String: Any]) -> Void) throws {
        let url = file(agent), fm = FileManager.default
        var root: [String: Any] = [:]
        if fm.fileExists(atPath: url.path) {
            guard let r = read(url) else { throw NSError(domain: "Perch", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(url.path) is not plain JSON"]) }
            root = r
            let backup = url.appendingPathExtension("before-perch")
            if !fm.fileExists(atPath: backup.path) { try? fm.copyItem(at: url, to: backup) }
        } else {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        change(&hooks)
        root["hooks"] = hooks.isEmpty ? nil : hooks
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}
