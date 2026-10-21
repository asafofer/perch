import AppKit
import ApplicationServices
import PerchCore

/// Starts a new session. In the Claude and Codex apps: their own link for a new session opens it with your words in the
/// message field (`claude://code/new?q=&folder=`, `codex://threads/new?prompt=&path=`), and Send is pressed through
/// Accessibility. Both apps come forward for a link, so Perch puts you back where you were unless you asked to go there.
/// In a terminal: a new window of the terminal you use runs the agent with your words as its first message.
/// Whether the session really began is told by the scan (`NewSession.started`), not here.
enum NewSessionStarter {
    /// Runs off the main thread. False when the words could not be sent: the app is left in front with them in its field,
    /// so nothing is lost. `needsYou` runs (on the main thread) when the app first asks you to trust the folder: a link
    /// that names a folder asks, and that is yours to answer, so Perch waits for it and presses Send after. `declined`
    /// runs (on the main thread) when you answer Cancel there: the session will not start.
    static func start(_ choice: NewSession.Choice, folder: String?, prompt: String, sessionId: String?, model: String = "", needsYou: @escaping @Sendable () -> Void, declined: @escaping @Sendable () -> Void = {}) -> Bool {
        if choice.terminal {
            let cwd = folder ?? NSHomeDirectory()
            Terminals.open(NewSession.command(agent: choice.agent, prompt: prompt, sessionId: sessionId, model: model), in: cwd, app: Terminals.preferred)
            return true
        }
        var c = URLComponents()
        if choice.agent == "codex" {
            c.scheme = "codex"; c.host = "threads"; c.path = "/new"
            c.queryItems = [URLQueryItem(name: "prompt", value: prompt)] + (folder.map { [URLQueryItem(name: "path", value: $0)] } ?? [])
        } else {
            c.scheme = "claude"; c.host = "code"; c.path = "/new"
            c.queryItems = [URLQueryItem(name: "q", value: prompt)] + (folder.map { [URLQueryItem(name: "folder", value: $0)] } ?? [])
        }
        // `+` reads as a space in a query: spell it out
        c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = c.url else { return false }
        let bundle = choice.agent == "codex" ? Restorer.codexApp : Restorer.claudeApp
        DispatchQueue.main.sync { _ = NSWorkspace.shared.open(url) }
        // Claude's link names the folder but starts the session with none: Perch picks the folder's project in Claude's menu.
        // Claude has no project for it: the folder is yours to pick there.
        var name = folder.map { ($0 as NSString).lastPathComponent }, pick: String?
        if let folder, bundle == Restorer.claudeApp {
            pick = (try? Data(contentsOf: NewSession.claudePresets)).flatMap { NewSession.claudeProject(for: folder, presets: $0) }
            if pick == nil { NSLog("Perch: Claude has no project on \(folder); the folder is yours to pick there") }
            name = pick
        }
        return pressSend(in: bundle, words: prompt, folder: folder == nil ? nil : name, base: folder.map { ($0 as NSString).lastPathComponent },
                         pick: folder != nil && bundle == Restorer.claudeApp, needsYou: needsYou, declined: declined)
    }

    /// Waits for the app's message field to hold exactly these words, then presses its Send. When the app asks you to
    /// trust the folder, the answer is yours, in the app (the notch says Confirm in Claude). Once you trust it, Claude's
    /// folder menu names your folder and the words are still in the field, and Perch sends them; a Cancel leaves no such
    /// folder, so it stays a Cancel. Codex shows no folder to check, so after its question Send is yours. (Trust pressed
    /// through Accessibility is not taken as yours: Claude then starts the session with no folder.)
    /// folder: the name Claude's menu shows for it (nil in Claude: none it knows, so you pick it there). pick: Perch chooses it
    /// in Claude's project menu before Send. base: the folder's own name, which Claude's menu may show after a trust question.
    private static func pressSend(in bundle: String, words: String, folder: String?, base: String? = nil, pick: Bool = false, needsYou: @escaping @Sendable () -> Void, declined: @escaping @Sendable () -> Void) -> Bool {
        guard AXIsProcessTrusted() else { NSLog("Perch: new session not sent (no Accessibility)"); return false }
        let want = squash(words), began = Date()
        var asked = false, sawField = false, folderBy: Date?, picked = false
        while Date().timeIntervalSince(began) < (asked ? 120 : 20) {
            defer { Thread.sleep(forTimeInterval: 0.2) }
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else { continue }
            let ax = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(ax, 1)
            AXUIElementSetAttributeValue(ax, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            let windows = (attr(ax, kAXWindowsAttribute) as? [AXUIElement]) ?? []
            // The question comes first: while it shows, the app hides its message field, which is not the words leaving it.
            let asking = asksTrust(windows)
            if !asked, asking { asked = true; NSLog("Perch: \(bundle) asks to trust the folder"); DispatchQueue.main.async { needsYou() } }
            let field = windows.lazy.compactMap { w in first(in: w, { role($0) == "AXTextArea" && classes($0).contains("ProseMirror") && squash(value($0)) == want }) }.first
            if let field {
                sawField = true
                // A folder Claude has no project for: Send is yours, after picking the folder there.
                if pick, folder == nil, !asking { DispatchQueue.main.async { needsYou() }; return false }
                // Asked to trust and answered: in Claude, the folder check below tells Trust (your folder) from Cancel.
                if asked, !asking, folder == nil || bundle != Restorer.claudeApp { NSLog("Perch: the trust question was answered in the app; Send is left to you"); return false }
                // Never into another folder than the one you chose: Claude's own folder menu by the field must name it
                // (after a trust question it can take a moment). Not there in a few seconds, Send is left to you.
                if let folder, bundle == Restorer.claudeApp, !asking {
                    // Not after a trust question: there the menu tells your Trust from your Cancel. Not chosen, Send is
                    // yours: the menu may name the project all the same while the session would start with none.
                    if pick, !picked, !asked {
                        guard choose(folder, near: field, in: app) else { DispatchQueue.main.async { needsYou() }; return false }
                        picked = true
                    }
                    let shown = folderMenus(near: field)
                    // After Trust, Claude may name the folder itself ("Folder: ~/path") rather than its project.
                    if !shown.contains(folder), !(pick && !picked && asked && base.map(shown.contains) == true) {
                        if folderBy == nil { folderBy = Date().addingTimeInterval(6) }
                        if Date() < folderBy! { continue }
                        NSLog("Perch: Claude shows \(shown) rather than \(folder); Send is left to you")
                        // Asked, and now on another folder: that was Cancel.
                        if asked { DispatchQueue.main.async { declined() } }
                        return false
                    }
                    // Trusted: chosen in the menu again all the same, as the link's folder alone starts it with none.
                    if pick, !picked {
                        guard choose(folder, near: field, in: app) else { DispatchQueue.main.async { needsYou() }; return false }
                        picked = true; continue
                    }
                    if asked { NSLog("Perch: trusted in Claude, on \(folder); sending") }
                }
                if let send = sendButton(near: field), (attr(send, kAXEnabledAttribute) as? Bool) != false, !asking {
                    guard AXUIElementPerformAction(send, kAXPressAction as CFString) == .success else { NSLog("Perch: new session not sent (Send did not press)"); return false }
                    if wait(3, { squash(value(field)).isEmpty ? true : nil }) == nil { NSLog("Perch: the new session's field still holds the words after Send") }
                    NSLog("Perch: started a new session in \(bundle)")
                    // Claude asks to trust the folder only now, on Send: a moment to see whether it does, then your answer.
                    if wait(2.5, { asksTrust(windowsOf(app)) ? true : nil }) != nil {
                        NSLog("Perch: \(bundle) asks to trust the folder"); DispatchQueue.main.async { needsYou() }
                        return awaitTrust(in: app)
                    }
                    return true
                }
            } else if sawField, !asked, !asking {
                // The words left the field without Perch: sent by you, or the page changed. The scan says which.
                NSLog("Perch: the new session's words left the field"); return false
            }
        }
        NSLog("Perch: new session not sent (\(sawField ? "no Send to press" : "its words never showed in the field"))")
        return false
    }
    /// The titles of the menus by the message field (Claude: Local, the folder, ...), a few levels up from it. Claude now
    /// leaves the folder menu's title empty and names it in its description, "Folder: ~/path": that counts as the folder's name.
    private static func folderMenus(near field: AXUIElement) -> [String] {
        var box = field
        for _ in 0..<7 { guard let up = attr(box, kAXParentAttribute) else { break }; box = up as! AXUIElement }
        var out: [String] = [], stack = [box], seen = 0
        while let e = stack.popLast(), seen < 600 {
            seen += 1
            if role(e) == "AXPopUpButton" {
                let t = string(e, kAXTitleAttribute), d = string(e, kAXDescriptionAttribute)
                if !t.isEmpty { out.append(t) }
                if d.hasPrefix("Folder: ") { out.append((String(d.dropFirst(8)) as NSString).lastPathComponent) }
                // Claude now calls its projects environments: "Environment: perch".
                if d.hasPrefix("Environment: ") { out.append(String(d.dropFirst(13))) }
            }
            stack.append(contentsOf: (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [])
        }
        return out
    }
    /// Chooses the project by this name in Claude's menu by the field (Environment: ...), looking under More when it is not
    /// among the recent ones. False when it could not: the menu is closed again and Send is left to you.
    private static func choose(_ name: String, near field: AXUIElement, in app: NSRunningApplication) -> Bool {
        var box = field, menu: AXUIElement?
        for _ in 0..<7 {
            guard let up = attr(box, kAXParentAttribute) else { break }
            box = up as! AXUIElement
            menu = first(in: box, limit: 600, { role($0) == "AXPopUpButton" && string($0, kAXDescriptionAttribute).hasPrefix("Environment: ") })
            if menu != nil { break }
        }
        guard let menu, AXUIElementPerformAction(menu, kAXPressAction as CFString) == .success else { NSLog("Perch: no project menu in Claude"); return false }
        // An item reads "perch , edit environment, right arrow".
        func item(_ match: @escaping (String) -> Bool) -> AXUIElement? {
            wait(1.5, { windowsOf(app).lazy.compactMap { w in first(in: w, { role($0) == "AXMenuItem" && match(string($0, kAXTitleAttribute)) }) }.first })
        }
        let mine: (String) -> Bool = { $0 == name || $0.hasPrefix(name + " ,") }
        var found = item(mine)
        if found == nil, let more = item({ $0.hasPrefix("More") }) {
            _ = AXUIElementPerformAction(more, kAXPressAction as CFString)
            found = item(mine)
        }
        if let found, AXUIElementPerformAction(found, kAXPressAction as CFString) == .success { NSLog("Perch: chose \(name) in Claude"); return true }
        NSLog("Perch: \(name) is not in Claude's project menu")
        for down in [true, false] { CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: down)?.postToPid(app.processIdentifier) }
        return false
    }
    /// The app's windows, the question a new session asks among them.
    private static func windowsOf(_ app: NSRunningApplication) -> [AXUIElement] {
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 1)
        return (attr(ax, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    }
    /// Asked to trust after Send: the answer is yours, in the app. Waits for it (it goes on by itself once trusted), at
    /// most two minutes; the scan says whether the session began.
    private static func awaitTrust(in app: NSRunningApplication) -> Bool {
        let began = Date()
        while Date().timeIntervalSince(began) < 120, asksTrust(windowsOf(app)) { Thread.sleep(forTimeInterval: 0.3) }
        return true
    }

    /// The app asks whether to trust the folder (Claude: Trust workspace, Codex: Trust folder).
    private static let trustTitles = ["Trust workspace", "Trust folder"]
    private static func asksTrust(_ windows: [AXUIElement]) -> Bool {
        windows.contains { w in first(in: w, { role($0) == "AXButton" && trustTitles.contains(string($0, kAXTitleAttribute)) }) != nil }
    }
    /// Send sits beside the field, a few levels up.
    private static func sendButton(near field: AXUIElement) -> AXUIElement? {
        var box = field
        for _ in 0..<6 {
            guard let up = attr(box, kAXParentAttribute) else { break }
            box = up as! AXUIElement
            if let b = first(in: box, limit: 300, { role($0) == "AXButton" && (string($0, kAXDescriptionAttribute) == "Send" || string($0, kAXTitleAttribute) == "Send") }) { return b }
        }
        return nil
    }

    /// Words compared without the line breaks and spacing an editor adds.
    private static func squash(_ s: String) -> String { s.split(whereSeparator: \.isWhitespace).joined(separator: " ") }

    private static func attr(_ e: AXUIElement, _ name: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
    }
    private static func string(_ e: AXUIElement, _ name: String) -> String { attr(e, name) as? String ?? "" }
    private static func role(_ e: AXUIElement) -> String { string(e, kAXRoleAttribute) }
    private static func value(_ e: AXUIElement) -> String { string(e, kAXValueAttribute) }
    private static func classes(_ e: AXUIElement) -> [String] { attr(e, "AXDOMClassList") as? [String] ?? [] }
    private static func first(in root: AXUIElement, limit: Int = 8000, _ match: (AXUIElement) -> Bool) -> AXUIElement? {
        var stack = [root], seen = 0
        while let e = stack.popLast(), seen < limit {
            seen += 1
            if match(e) { return e }
            stack.append(contentsOf: ((attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? []).reversed())
        }
        return nil
    }
    private static func wait<T>(_ seconds: Double, _ check: () -> T?) -> T? {
        let end = Date().addingTimeInterval(seconds)
        repeat {
            if let v = check() { return v }
            Thread.sleep(forTimeInterval: 0.15)
        } while Date() < end
        return nil
    }
}
