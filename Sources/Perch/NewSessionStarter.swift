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
    /// that names a folder asks, and that is yours to answer, so Perch waits for it and presses Send after.
    static func start(_ choice: NewSession.Choice, folder: String?, prompt: String, sessionId: String?, needsYou: @escaping @Sendable () -> Void) -> Bool {
        if choice.terminal {
            let cwd = folder ?? NSHomeDirectory()
            Terminals.open(NewSession.command(agent: choice.agent, prompt: prompt, sessionId: sessionId), in: cwd, app: Terminals.preferred)
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
        return pressSend(in: bundle, words: prompt, folder: folder.map { ($0 as NSString).lastPathComponent }, needsYou: needsYou)
    }

    /// Your answer, from the notch, to the app asking to trust the new session's folder. Set on the main thread, taken
    /// by the thread that drives the app.
    final class Trust: @unchecked Sendable {
        enum Answer { case trust, cancel }
        private let lock = NSLock(); private var given: Answer?
        func answer(_ a: Answer) { lock.lock(); given = a; lock.unlock() }
        func take() -> Answer? { lock.lock(); defer { given = nil; lock.unlock() }; return given }
        func reset() { lock.lock(); given = nil; lock.unlock() }
    }
    static let trust = Trust()

    /// Waits for the app's message field to hold exactly these words, then presses its Send. While the app asks you to
    /// trust the folder it waits longer, for your answer on the notch: Perch presses the app's Trust workspace or Cancel
    /// for you. Answered in the app itself, Perch never presses Send after it: a Cancel there stays a Cancel.
    private static func pressSend(in bundle: String, words: String, folder: String?, needsYou: @escaping @Sendable () -> Void) -> Bool {
        guard AXIsProcessTrusted() else { NSLog("Perch: new session not sent (no Accessibility)"); return false }
        let want = squash(words), began = Date()
        var asked = false, sawField = false, trusted = false, folderBy: Date?
        trust.reset()
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
            if asked, let a = trust.take() {
                let title = a == .trust ? trustTitles : ["Cancel", "Don't trust", "Don\u{2019}t trust"]
                let b = windows.lazy.compactMap({ w in first(in: w, { role($0) == "AXButton" && title.contains(string($0, kAXTitleAttribute)) && inTrustDialog($0) }) }).first
                let pressed = b.map { AXUIElementPerformAction($0, kAXPressAction as CFString) == .success } ?? false
                NSLog("Perch: \(a == .trust ? "Trust" : "Cancel") \(pressed ? "pressed" : "not found") in \(bundle)")
                if a == .cancel { NSLog("Perch: the new session's folder was not trusted; nothing sent"); return false }
                trusted = true; continue
            }
            if let field {
                sawField = true
                // Asked to trust and answered in the app, not from the notch: the rest is yours there.
                if asked, !trusted, !asking { NSLog("Perch: the trust question was answered in the app; Send is left to you"); return false }
                // Never into another folder than the one you chose: Claude's own folder menu by the field must name it
                // (after a trust question it can take a moment). Not there in a few seconds, Send is left to you.
                if let folder, bundle == Restorer.claudeApp, !asking {
                    let shown = folderMenus(near: field)
                    if !shown.contains(folder) {
                        if folderBy == nil { folderBy = Date().addingTimeInterval(6) }
                        if Date() < folderBy! { continue }
                        NSLog("Perch: Claude shows \(shown) rather than \(folder); Send is left to you"); return false
                    }
                }
                if let send = sendButton(near: field), (attr(send, kAXEnabledAttribute) as? Bool) != false, !asking {
                    guard AXUIElementPerformAction(send, kAXPressAction as CFString) == .success else { NSLog("Perch: new session not sent (Send did not press)"); return false }
                    if wait(3, { squash(value(field)).isEmpty ? true : nil }) == nil { NSLog("Perch: the new session's field still holds the words after Send") }
                    NSLog("Perch: started a new session in \(bundle)")
                    // Claude asks to trust the folder only now, on Send: a moment to see whether it does, then your answer.
                    if !trusted, wait(2.5, { asksTrust(windowsOf(app)) ? true : nil }) != nil {
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
    /// The titles of the menus by the message field (Claude: Local, the folder, ...), a few levels up from it.
    private static func folderMenus(near field: AXUIElement) -> [String] {
        var box = field
        for _ in 0..<7 { guard let up = attr(box, kAXParentAttribute) else { break }; box = up as! AXUIElement }
        var out: [String] = [], stack = [box], seen = 0
        while let e = stack.popLast(), seen < 600 {
            seen += 1
            if role(e) == "AXPopUpButton" { let t = string(e, kAXTitleAttribute); if !t.isEmpty { out.append(t) } }
            stack.append(contentsOf: (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [])
        }
        return out
    }
    /// The app's windows, the question a new session asks among them.
    private static func windowsOf(_ app: NSRunningApplication) -> [AXUIElement] {
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 1)
        return (attr(ax, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    }
    /// Asked to trust after Send: your answer from the notch presses the app's own button (true: trusted, it goes on). The
    /// question answered in the app, or never, is yours: true, and the scan says whether the session began.
    private static func awaitTrust(in app: NSRunningApplication) -> Bool {
        let began = Date()
        while Date().timeIntervalSince(began) < 120 {
            let windows = windowsOf(app)
            guard asksTrust(windows) else { return true }
            if let a = trust.take() {
                let title = a == .trust ? trustTitles : ["Cancel", "Don't trust", "Don\u{2019}t trust"]
                if let b = windows.lazy.compactMap({ w in first(in: w, { role($0) == "AXButton" && title.contains(string($0, kAXTitleAttribute)) && inTrustDialog($0) }) }).first {
                    _ = AXUIElementPerformAction(b, kAXPressAction as CFString)
                }
                if a == .cancel { NSLog("Perch: the new session's folder was not trusted"); return false }
                return true
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return true
    }

    /// The app asks whether to trust the folder (Claude: Trust workspace, Codex: Trust folder).
    private static let trustTitles = ["Trust workspace", "Trust folder"]
    private static func asksTrust(_ windows: [AXUIElement]) -> Bool {
        windows.contains { w in first(in: w, { role($0) == "AXButton" && trustTitles.contains(string($0, kAXTitleAttribute)) }) != nil }
    }
    /// A button of the trust question itself (its Cancel, not some other Cancel in the window): one that shares a parent
    /// with a Trust button, a few levels up.
    private static func inTrustDialog(_ b: AXUIElement) -> Bool {
        var box = b
        for _ in 0..<4 {
            guard let up = attr(box, kAXParentAttribute) else { return false }
            box = up as! AXUIElement
            if first(in: box, limit: 400, { role($0) == "AXButton" && trustTitles.contains(string($0, kAXTitleAttribute)) }) != nil { return true }
        }
        return false
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
