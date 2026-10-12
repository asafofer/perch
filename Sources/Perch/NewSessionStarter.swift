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
    /// so nothing is lost.
    static func start(_ choice: NewSession.Choice, folder: String?, prompt: String, sessionId: String?) -> Bool {
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
        return pressSend(in: bundle, words: prompt)
    }

    /// Waits for the app's message field to hold exactly these words, then presses its Send.
    private static func pressSend(in bundle: String, words: String) -> Bool {
        guard AXIsProcessTrusted() else { NSLog("Perch: new session not sent (no Accessibility)"); return false }
        let want = squash(words)
        let field = wait(20) { () -> AXUIElement? in
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else { return nil }
            let ax = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(ax, 1)
            AXUIElementSetAttributeValue(ax, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            for w in (attr(ax, kAXWindowsAttribute) as? [AXUIElement]) ?? [] {
                if let f = first(in: w, { role($0) == "AXTextArea" && classes($0).contains("ProseMirror") && squash(value($0)) == want }) { return f }
            }
            return nil
        }
        guard let field else { NSLog("Perch: new session not sent (its words never showed in the field)"); return false }
        let send = wait(3) { () -> AXUIElement? in
            guard let b = sendButton(near: field), (attr(b, kAXEnabledAttribute) as? Bool) != false else { return nil }
            return b
        }
        guard let send, AXUIElementPerformAction(send, kAXPressAction as CFString) == .success else { NSLog("Perch: new session not sent (no Send to press)"); return false }
        if wait(3, { squash(value(field)).isEmpty ? true : nil }) == nil { NSLog("Perch: the new session's field still holds the words after Send") }
        NSLog("Perch: started a new session in \(bundle)")
        return true
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
