import Foundation
import PerchCore

/// Listens on a Unix socket for what Claude Code and Codex hooks, and Perch's OpenCode plugin and pi extension, post
/// (see HookInstaller), one small HTTP request each.
/// Status events are answered at once. A request Perch can answer from the notch is held open until you choose,
/// it is settled elsewhere, or the hook goes away; whichever happens first.
final class HookServer: @unchecked Sendable {
    var onEvent: (@MainActor (HookEvent) -> Void)?
    /// A held request's hook went away: answered in the app, or the session ended.
    var onAbandoned: (@MainActor (String) -> Void)?
    /// Whether a question held by the PreToolUse hook should stay held: false once you are in that session, where the app's own
    /// prompt is what you want (the hook keeps that prompt from showing until it is let go).
    var keepHolding: (@MainActor (String) -> Bool)?

    private let queue = DispatchQueue(label: "perch.hooks")
    private var listener: DispatchSourceRead?
    private var held: [String: (fd: Int32, watch: DispatchSourceRead)] = [:]
    /// Questions held by PreToolUse: checked every second, and let go after their time.
    private var timers: [String: DispatchSourceTimer] = [:]

    func start() {
        let path = HookInstaller.socket.path
        try? FileManager.default.createDirectory(at: HookInstaller.dir, withIntermediateDirectories: true)
        unlink(path)
        #if os(Linux)
        let fd = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
        #else
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        #endif
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

    /// Answers a held request. An empty body means "no decision": the app's own prompt decides. `done` hears, on the main
    /// thread, whether it reached the hook: false when it came too late (answered in the app, or let go).
    func answer(_ askId: String, with body: Data, done: (@MainActor (Bool) -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self, let h = self.held.removeValue(forKey: askId) else {
                Self.trace("answer for \(askId.prefix(8)) came too late: no longer held")
                if let done { DispatchQueue.main.async { MainActor.assumeIsolated { done(false) } } }
                return
            }
            Self.trace("answered \(askId.prefix(8)): \(String(decoding: body.prefix(400), as: UTF8.self))")
            h.watch.cancel(); self.timers.removeValue(forKey: askId)?.cancel()
            Self.respond(h.fd, body)
            if let done { DispatchQueue.main.async { MainActor.assumeIsolated { done(true) } } }
        }
    }
    func release(_ askId: String) { answer(askId, with: Data()) }

    /// A PreToolUse hold that has run its time, or that you walked in on: the agent's own prompt shows, and the card stops offering the answer.
    private func letGo(_ id: String) {
        guard let h = held.removeValue(forKey: id) else { return }
        h.watch.cancel(); timers.removeValue(forKey: id)?.cancel()
        Self.trace("\(id.prefix(8)) let go without an answer")
        Self.respond(h.fd, Data())
        DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.onAbandoned?(id) } }
    }

    private func handle(_ c: Int32) {
        #if !os(Linux)
        var one: Int32 = 1
        setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        #endif
        var tv = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        guard let (path, body, headers) = Self.readRequest(c) else { close(c); return }
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count == 2, Agent.all.contains(where: { $0.id == parts[0] }) else { Self.respond(c, Data()); return }
        let id = UUID().uuidString
        guard var event = HookEvent.parse(agent: parts[0], event: parts[1], body: body, requestId: id, pid: headers["x-perch-pid"].flatMap { Int32($0) }) else { Self.respond(c, Data()); return }
        if let pid = event.pid { SessionPids.note(event.sessionId, pid: pid) }
        // Only the Claude app runs this hook alongside its own prompt, and Perch's OpenCode plugin asks without blocking
        // OpenCode's. Anywhere else (a terminal, `claude -p`) the prompt waits for the hook, so holding it would freeze the
        // session: those are answered at once, with no decision.
        var alongside = event.agent == "opencode" || DesktopSessions.shared.index()[event.sessionId] != nil
        // The PreToolUse hook is not alongside the app's prompt: the prompt waits for it. So it is held only while you are
        // elsewhere, and only for as long as the notch keeps offering the question.
        if case .asks(let ask) = event.kind, ask.viaPreToolUse, alongside {
            let sid = event.sessionId
            alongside = DispatchQueue.main.sync { MainActor.assumeIsolated { self.keepHolding?(sid) ?? true } }
        }
        if case .asks(let ask) = event.kind, ask.answerable, alongside {
            // Hold the hook open. If it goes away first (the app answered, the session ended), say so.
            let watch = DispatchSource.makeReadSource(fileDescriptor: c, queue: queue)
            watch.setEventHandler { [weak self] in
                guard let self, self.held[id] != nil else { return }
                var b: UInt8 = 0
                if recv(c, &b, 1, Int32(MSG_PEEK)) <= 0 {
                    Self.trace("\(id.prefix(8)) closed by the app before Perch answered")
                    self.held[id]?.watch.cancel(); self.held[id] = nil; self.timers.removeValue(forKey: id)?.cancel(); close(c)
                    DispatchQueue.main.async { MainActor.assumeIsolated { self.onAbandoned?(id) } }
                }
            }
            held[id] = (c, watch)
            watch.resume()
            if ask.viaPreToolUse {
                let sid = event.sessionId, until = Date().addingTimeInterval(TimeInterval(9 + Prefs.questionSeconds))
                let t = DispatchSource.makeTimerSource(queue: queue)
                t.schedule(deadline: .now() + 1, repeating: 1)
                t.setEventHandler { [weak self] in
                    guard let self, self.held[id] != nil else { return }
                    if Date() >= until { self.letGo(id); return }
                    DispatchQueue.main.async { MainActor.assumeIsolated {
                        if self.keepHolding?(sid) == false { self.queue.async { self.letGo(id) } }
                    } }
                }
                timers[id] = t
                t.resume()
            }
            Self.trace("holding \(id.prefix(8)) for \(event.sessionId.prefix(8)): \(ask.kind)")
        } else {
            Self.respond(c, Data())
            // Answered already (with no decision): the card shows it, and Pick up takes you to where it is asked.
            if case .asks(var ask) = event.kind, ask.answerable {
                ask.answerable = false
                let pid = event.pid
                event = HookEvent(agent: event.agent, sessionId: event.sessionId, kind: .asks(ask), at: event.at); event.pid = pid
            }
        }
        let sent = event
        DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.onEvent?(sent) } }
    }

    /// Request path, body and headers (names in lowercase) of a small HTTP POST. Nil when it is not one.
    private static func readRequest(_ c: Int32) -> (String, Data, [String: String])? {
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
        let lines = head.split(separator: "\r\n")
        let request = lines.first?.split(separator: " ") ?? []
        guard request.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        return (String(request[1]), Data(data[r.upperBound...].prefix(length)), headers)
    }

    /// With PERCH_TRACE set: what happens to each request Perch holds.
    /// Linux has no SO_NOSIGPIPE: a hook gone before its answer must not kill Perch, so each send says so itself.
    #if os(Linux)
    private static let noSigPipe = Int32(MSG_NOSIGNAL)
    #else
    private static let noSigPipe: Int32 = 0
    #endif
    private static func trace(_ s: String) { if ProcessInfo.processInfo.environment["PERCH_TRACE"] != nil { NSLog("Perch hook: \(s)") } }

    private static func respond(_ c: Int32, _ body: Data) {
        let head = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        let out = Data(head.utf8) + body
        out.withUnsafeBytes { p in var sent = 0; while sent < out.count { let n = send(c, p.baseAddress! + sent, out.count - sent, Self.noSigPipe); if n <= 0 { break }; sent += n } }
        close(c)
    }
}

/// Which process last spoke for each session through a hook: its own (the plugins) or the hook's parent (the hook script).
/// The scan follows it up to the agent process, which says exactly which running agent each session is.
enum SessionPids {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var map: [String: (pid: Int32, at: Date)] = [:]
    static func note(_ session: String, pid: Int32) {
        lock.lock(); defer { lock.unlock() }
        map[session] = (pid, Date())
        if map.count > 200 { map = Dictionary(uniqueKeysWithValues: map.sorted { $0.value.at > $1.value.at }.prefix(120).map { ($0.key, $0.value) }) }
    }
    static func all() -> [String: (pid: Int32, at: Date)] { lock.lock(); defer { lock.unlock() }; return map }
}

/// Installs the hook script and the config entries that run it, or for OpenCode and pi, Perch's own plugin file.
/// Perch only touches entries and files it wrote itself.
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
    [ "$1" = claude ] && { [ "$2" = PermissionRequest ] || [ "$2" = PreToolUse ]; } && wait=3600
    out=$(/usr/bin/curl -s --max-time "$wait" --unix-socket "$sock" -H 'Expect:' -H 'Content-Type: application/json' -H "X-Perch-Pid: $PPID" --data-binary @- "http://perch/$1/$2" 2>/dev/null) || exit 0
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
        // Bypass permissions mode sends no PermissionRequest for a question, but this hook still runs.
        Hook(event: "PreToolUse", matcher: "AskUserQuestion", async: false, timeout: 3600),
    ]
    static let codexHooks_ = [
        Hook(event: "UserPromptSubmit", matcher: nil, async: false, timeout: 5),
        Hook(event: "PostToolUse", matcher: "*", async: false, timeout: 5),
        Hook(event: "Stop", matcher: nil, async: false, timeout: 5),
        Hook(event: "PermissionRequest", matcher: "*", async: false, timeout: 5),
        Hook(event: "Interrupt", matcher: nil, async: false, timeout: 3),
    ]

    /// The agents Perch can install a hook for.
    static let agents = ["claude", "codex", "opencode", "pi"]
    static func file(_ agent: String) -> URL { agent == "codex" ? codexHooks : claudeSettings }
    /// OpenCode and pi load every plugin in a folder: Perch adds its own file there and removes only that file.
    static let pluginFiles: [String: URL] = [
        "opencode": home.appendingPathComponent(".config/opencode/plugins/perch.js"),
        "pi": home.appendingPathComponent(".pi/agent/extensions/perch.ts"),
    ]
    /// The first line of each plugin file, which says it is Perch's.
    static let pluginMark = "// Perch: "
    static func hooks(_ agent: String) -> [Hook] { agent == "codex" ? codexHooks_ : claudeHooks }

    static func isInstalled(_ agent: String) -> Bool {
        if let f = pluginFiles[agent] { return (try? String(contentsOf: f, encoding: .utf8))?.hasPrefix(pluginMark) == true }
        guard FileManager.default.isExecutableFile(atPath: script.path),
              let root = read(file(agent)), let hooks = root["hooks"] as? [String: Any] else { return false }
        return Self.hooks(agent).allSatisfy { h in (hooks[h.event] as? [[String: Any]] ?? []).contains(where: isOurs) }
    }

    static func install(_ agent: String) throws {
        if let f = pluginFiles[agent], let body = PerchPlugins.body[agent] {
            // Someone else's file by that name is left alone.
            if FileManager.default.fileExists(atPath: f.path), !isInstalled(agent) {
                throw NSError(domain: "Perch", code: 2, userInfo: [NSLocalizedDescriptionKey: "\(f.path) is not Perch's"])
            }
            try FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
            try body.write(to: f, atomically: true, encoding: .utf8)
            return
        }
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

    /// Hooks installed by an earlier Perch lack the newest entries: add them, so Live status does not read off after an update.
    static func upgrade() {
        for agent in agents where pluginFiles[agent] == nil && !isInstalled(agent) {
            guard FileManager.default.isExecutableFile(atPath: script.path), let root = read(file(agent)),
                  let hooks = root["hooks"] as? [String: Any],
                  hooks.values.contains(where: { ($0 as? [[String: Any]] ?? []).contains(where: isOurs) }) else { continue }
            try? install(agent)
        }
    }

    static func uninstall(_ agent: String) throws {
        if let f = pluginFiles[agent] {
            if isInstalled(agent) { try FileManager.default.removeItem(at: f) }
            return
        }
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
