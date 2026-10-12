import CPerchLinux
import Foundation

/// Moments when Perch must not speak up on its own: a call, the camera on, a presentation on screen, a launcher open.
/// Hover and the shortcuts still work; only the proactive card waits.
enum Quiet {
    /// Dictation apps open the mic for a moment while you talk to them. That is not a call.
    private static let dictation = ["nerd-dictation", "whisper", "speech", "dictation", "talon", "numen", "handy"]
    /// Slideshow apps (WM_CLASS, lowercased).
    private static let presenters: Set<String> = ["libreoffice-impress", "soffice", "libreoffice", "pdfpc", "pympress", "impressive", "okular",
                                                  "evince", "wpp", "onlyoffice", "desktopeditors"]
    /// Launchers and menus that take the keyboard, by WM_CLASS, with the name Perch gives them. Xfce's Whisker menu runs
    /// in a panel plugin wrapper (wrapper-2.0); xfrun4 is xfce4-appfinder.
    private static let launchers: [String: String] = [
        "rofi": "Rofi", "ulauncher": "Ulauncher", "albert": "Albert", "xfce4-appfinder": "Application Finder", "wrapper-2.0": "A panel menu",
        "xfce4-panel": "A panel menu", "krunner": "KRunner", "dmenu": "dmenu", "synapse": "Synapse", "kupfer": "Kupfer", "cerebro": "Cerebro",
        "fuzzel": "Fuzzel", "wofi": "Wofi", "jgmenu": "jgmenu",
    ]

    /// Why Perch should wait, or nil when it is fine to show the card.
    @MainActor static func reason() -> String? {
        if let app = appUsingMic() { return "the mic is in use by \(app)" }
        if cameraInUse() { return "the camera is on" }
        if presenting() { return "a presentation is on screen" }
        if let app = launcherOpen() { return "\(app) has the keyboard" }
        return nil
    }

    /// A launcher has the keyboard: the active window, the window holding the focus, or an override-redirect window on
    /// top (Rofi and dmenu map one and grab the keyboard without taking the focus) belongs to one. X property reads only,
    /// cheap enough for every hover.
    @MainActor static func launcherOpen() -> String? {
        guard let d = X11.display else { return nil }
        var windows: [Window] = []
        if let a = X11.activeWindow() { windows.append(a) }
        var focus: Window = 0, revert: Int32 = 0
        XGetInputFocus(d, &focus, &revert)
        if focus > 1 { windows.append(focus) }   // 0 is None, 1 PointerRoot
        windows += topOverrideRedirect(d, count: 6)
        for w in windows {
            guard let (app, owner) = classed(d, w), owner != getpid() else { continue }
            if let name = launchers[app] { return name }
        }
        return nil
    }

    /// The first app recording from a microphone (a source that is not a speaker's monitor, a stream that is not paused),
    /// from PulseAudio or PipeWire's pulse server. Without pactl, any ALSA capture device running counts, unnamed.
    static func appUsingMic() -> String? {
        // Only with a pulse server to ask (PipeWire's included): pactl with none may start a PulseAudio daemon itself.
        let env = ProcessInfo.processInfo.environment
        let sockets = [env["PULSE_RUNTIME_PATH"].map { "\($0)/native" }, env["XDG_RUNTIME_DIR"].map { "\($0)/pulse/native" }].compactMap { $0 }
        guard let pactl = which("pactl"), env["PULSE_SERVER"] != nil || sockets.contains(where: { FileManager.default.fileExists(atPath: $0) }) else {
            return alsaCapturing() ? "an app" : nil
        }
        guard let out = run(pactl, ["-f", "json", "list", "source-outputs"]),
              let streams = try? JSONSerialization.jsonObject(with: out) as? [[String: Any]], !streams.isEmpty else { return nil }
        var monitors: Set<Int>?
        let me = Int(getpid())
        for s in streams where (s["corked"] as? Bool) != true {
            let p = s["properties"] as? [String: Any] ?? [:]
            let app = (p["application.name"] as? String) ?? (p["application.process.binary"] as? String) ?? "an app"
            let binary = (p["application.process.binary"] as? String ?? "").lowercased()
            let id = (p["application.id"] as? String ?? "").lowercased()
            if Int(p["application.process.id"] as? String ?? "") == me { continue }
            if id.contains("pavucontrol") || (p["media.name"] as? String) == "Peak detect" { continue }   // a volume meter
            if dictation.contains(where: { binary.contains($0) || app.lowercased().contains($0) }) { continue }
            if monitors == nil {
                let list = run(pactl, ["-f", "json", "list", "sources", "short"]).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] } ?? []
                monitors = Set(list.compactMap { ($0["name"] as? String)?.hasSuffix(".monitor") == true ? $0["index"] as? Int : nil })
            }
            if let source = s["source"] as? Int, monitors?.contains(source) == true { continue }   // recording what plays, not a mic
            return app
        }
        return nil
    }

    /// A process holds a camera (/dev/video*) open. Nothing does while no app uses it: PipeWire opens it only to stream.
    static func cameraInUse() -> Bool {
        guard let devs = try? FileManager.default.contentsOfDirectory(atPath: "/dev"), devs.contains(where: { $0.hasPrefix("video") }),
              let pids = try? FileManager.default.contentsOfDirectory(atPath: "/proc") else { return false }
        var buf = [CChar](repeating: 0, count: 64)
        for pid in pids where pid.first?.isNumber == true {
            guard let dir = opendir("/proc/\(pid)/fd") else { continue }   // another user's: not readable, and not counted
            defer { closedir(dir) }
            while let ent = readdir(dir) {
                let name = withUnsafeBytes(of: ent.pointee.d_name) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
                guard name.first?.isNumber == true else { continue }
                let n = readlink("/proc/\(pid)/fd/\(name)", &buf, buf.count - 1)
                guard n > 10 else { continue }
                buf[n] = 0
                if String(cString: buf).hasPrefix("/dev/video") { return true }
            }
        }
        return false
    }

    /// A slideshow app is in front with a window filling a whole display (full screen, or a window that size).
    @MainActor static func presenting() -> Bool {
        guard let d = X11.display, let front = X11.activeWindow(), let app = X11.appId(of: front), presenters.contains(app) else { return false }
        let pid = X11.pid(of: front)
        let screens = Screen.screens.map { X11.flip($0.frame).size }
        let fullscreen = X11.atom("_NET_WM_STATE_FULLSCREEN")
        return managedWindows().contains { w in
            guard w == front || (pid != nil && X11.pid(of: w) == pid) || X11.appId(of: w) == app else { return false }
            if X11.cardinals(w, "_NET_WM_STATE", type: Atom(XA_ATOM)).contains(UInt(fullscreen)) { return true }
            var a = XWindowAttributes()
            guard XGetWindowAttributes(d, w, &a) != 0, a.map_state == IsViewable else { return false }
            return screens.contains { $0.width == CGFloat(a.width) && $0.height == CGFloat(a.height) }
        }
    }

    // MARK: plumbing

    /// The windows the window manager manages. xfwm4 (4.16 at least) keeps _NET_CLIENT_LIST but not always the stacking
    /// list X11.clientWindows reads, so the plain list stands in.
    static func managedWindows() -> [Window] {
        let stacked = X11.clientWindows()
        return stacked.isEmpty ? X11.cardinals(X11.root, "_NET_CLIENT_LIST", type: Atom(XA_WINDOW)).map { Window($0) } : stacked
    }

    /// A window's WM_CLASS and owner, from it or the nearest ancestor that has one (focus can sit on a child window).
    @MainActor private static func classed(_ d: OpaquePointer, _ start: Window) -> (String, pid_t?)? {
        var w = start
        for _ in 0..<6 {
            if let app = X11.appId(of: w) { return (app, X11.pid(of: w)) }
            var root: Window = 0, parent: Window = 0, kids: UnsafeMutablePointer<Window>?, n: UInt32 = 0
            guard XQueryTree(d, w, &root, &parent, &kids, &n) != 0 else { return nil }
            if let kids { XFree(kids) }
            if parent == 0 || parent == root { return nil }
            w = parent
        }
        return nil
    }

    /// The topmost mapped override-redirect windows (menus and launchers the window manager does not manage).
    @MainActor private static func topOverrideRedirect(_ d: OpaquePointer, count: Int) -> [Window] {
        var root: Window = 0, parent: Window = 0, kids: UnsafeMutablePointer<Window>?, n: UInt32 = 0
        guard XQueryTree(d, X11.root, &root, &parent, &kids, &n) != 0, let kids else { return [] }
        defer { XFree(kids) }
        var out: [Window] = []
        for i in stride(from: Int(n) - 1, through: max(0, Int(n) - count), by: -1) {
            var a = XWindowAttributes()
            if XGetWindowAttributes(d, kids[i], &a) != 0, a.override_redirect != 0, a.map_state == IsViewable { out.append(kids[i]) }
        }
        return out
    }

    /// ALSA's own view: a capture substream running (/proc/asound/card*/pcm*c/sub*/status).
    private static func alsaCapturing() -> Bool {
        let fm = FileManager.default
        guard let cards = try? fm.contentsOfDirectory(atPath: "/proc/asound") else { return false }
        for card in cards where card.hasPrefix("card") {
            for pcm in (try? fm.contentsOfDirectory(atPath: "/proc/asound/\(card)")) ?? [] where pcm.hasPrefix("pcm") && pcm.hasSuffix("c") {
                for sub in (try? fm.contentsOfDirectory(atPath: "/proc/asound/\(card)/\(pcm)")) ?? [] where sub.hasPrefix("sub") {
                    if let s = try? String(contentsOfFile: "/proc/asound/\(card)/\(pcm)/\(sub)/status", encoding: .utf8), s.contains("RUNNING") { return true }
                }
            }
        }
        return false
    }

    static func which(_ tool: String) -> String? {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        return (path.split(separator: ":").map { "\($0)/\(tool)" } + ["/usr/bin/\(tool)"]).first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// A tool's output, in the C locale, given up after a second and a half.
    static func run(_ tool: String, _ args: [String]) -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["LC_ALL"] = "C"
        p.environment = env
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) { if p.isRunning { p.terminate() } }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? data : nil
    }
}
