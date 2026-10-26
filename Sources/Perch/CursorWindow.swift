import AppKit
import PerchCore

/// Going back to a Cursor chat. Cursor's own link opens an existing chat in its Agents window and puts the cursor in its
/// prompt: `cursor://anysphere.cursor-deeplink/agent?id=<chat id>` (the id of the transcript). Without a chat id, or when
/// Cursor is not installed, the chat's folder opens instead.
enum CursorWindow {
    static func trace(_ s: String) { if ProcessInfo.processInfo.environment["PERCH_TRACE"] != nil { NSLog("Perch cursor: %@", s) } }
    static var appURL: URL? { AppIcons.url("cursor") }

    static func link(chat id: String) -> URL? {
        var parts = URLComponents(string: "cursor://anysphere.cursor-deeplink/agent")
        parts?.queryItems = [URLQueryItem(name: "id", value: id)]
        return parts?.url
    }

    /// Whether the chat was opened by its own link (the prompt then belongs to it, so a reply can be pasted).
    @discardableResult static func open(chat id: String?, folder: String?) -> Bool {
        guard let app = appURL else { return false }
        if let id, let url = link(chat: id) {
            let running = !NSRunningApplication.runningApplications(withBundleIdentifier: CursorApp.bundle).isEmpty
            NSWorkspace.shared.open(url)
            // Cursor drops a link that arrives while it is still starting: once its window is up, and shows no chat, send it again.
            if !running {
                DispatchQueue.global(qos: .userInitiated).async {
                    var tries = 0
                    for _ in 0..<60 {
                        Thread.sleep(forTimeInterval: 0.4)
                        tries += 1
                        if case .unreadable = showingNow() { continue }
                        break
                    }
                    Thread.sleep(forTimeInterval: 1)
                    let now = showingNow()
                    trace("Cursor started: window readable after \(tries) tries, shows \(now)")
                    if case .session = now { return }
                    trace("Cursor dropped the link while starting: sending it again")
                    NSWorkspace.shared.open(url)
                }
            }
            return true
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        guard let folder, !folder.hasSuffix("/.cursor/projects/\(CursorApp.noFolder)") else {
            NSWorkspace.shared.openApplication(at: app, configuration: config)
            return false
        }
        NSWorkspace.shared.open([URL(fileURLWithPath: folder, isDirectory: true)], withApplicationAt: app, configuration: config)
        return false
    }
}

extension CursorWindow {
    /// The chat the Agents window in front shows, by its title (the window names it in a button: "Chat title. <title>").
    /// `.none` when that window shows no chat (a new one); `.unreadable` for any other window or without Accessibility.
    /// Runs off the main thread.
    nonisolated static func showingNow() -> ClaudeComposer.Showing {
        guard AXIsProcessTrusted(), let app = NSRunningApplication.runningApplications(withBundleIdentifier: CursorApp.bundle).first else { return .unreadable }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 1)
        enableAccessibility(ax)
        guard let window = agentsWindow(ax) else { trace("no Agents window (windows: \((ConductorApp.attr(ax, kAXWindowsAttribute) as? [AXUIElement])?.count ?? -1))"); return .unreadable }
        guard let page = ConductorApp.first(in: [window], limit: 1500, { ConductorApp.attr($0, kAXRoleAttribute) as? String == "AXWebArea" }) else { trace("no web area in the Agents window"); enableAccessibility(ax, again: true); return .unreadable }
        guard (ConductorApp.attr(page, kAXTitleAttribute) as? String)?.contains("Agents") == true else { trace("web area titled \(ConductorApp.attr(page, kAXTitleAttribute) as? String ?? "nil")"); return .unreadable }
        let mark = "Chat title. "
        let hit = ConductorApp.first(in: [page], limit: 3000) {
            ConductorApp.attr($0, kAXRoleAttribute) as? String == "AXButton" && (ConductorApp.attr($0, kAXTitleAttribute) as? String)?.hasPrefix(mark) == true
        }
        guard let title = (hit.flatMap { ConductorApp.attr($0, kAXTitleAttribute) as? String })?.dropFirst(mark.count), !title.isEmpty else { return .none }
        return .session(String(title))
    }
}

extension CursorWindow {
    /// Electron builds its accessibility tree once asked (`AXManualAccessibility`), and asking again restarts it: so only once,
    /// else a window read every half second while Cursor starts never gets to see the tree fill.
    /// It is set again every few seconds while no web area shows: a window that opened after the first ask has no tree.
    nonisolated(unsafe) private static var lastAsked = Date.distantPast
    nonisolated static func enableAccessibility(_ ax: AXUIElement, again: Bool = false) {
        guard again || ConductorApp.attr(ax, "AXManualAccessibility") as? Bool != true, Date().timeIntervalSince(lastAsked) > 2.5 else { return }
        lastAsked = Date()
        AXUIElementSetAttributeValue(ax, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    /// Cursor's Agents window, found by its title: it is not the focused window while Cursor is still starting or behind another app.
    nonisolated static func agentsWindow(_ ax: AXUIElement) -> AXUIElement? {
        let windows = ConductorApp.attr(ax, kAXWindowsAttribute) as? [AXUIElement] ?? []
        return windows.first { (ConductorApp.attr($0, kAXTitleAttribute) as? String)?.contains("Agents") == true }
            ?? (ConductorApp.attr(ax, kAXFocusedWindowAttribute) as! AXUIElement?)
    }

    /// Whether the window's chat title is the one wanted. A title longer than the row's is clipped there.
    nonisolated static func matches(_ shown: String, _ want: String) -> Bool { shown == want || shown.hasPrefix(want) || want.hasPrefix(shown) }

    /// Answers what Cursor asks in the chat: opens the chat with its link, then presses the button of its prompt ("Run", or
    /// "Skip" to refuse), which Cursor shows in the chat itself. Nothing is pressed unless the window shows this very chat.
    /// Cursor's own hooks cannot answer it (they run for every command, ones Cursor runs unasked too). Blocks: call it off the main thread.
    nonisolated static func answer(chat: String, title: String, allow: Bool) -> Bool {
        guard AXIsProcessTrusted(), link(chat: chat) != nil else { return false }
        func showing() -> Bool { if case .session(let t) = showingNow() { return matches(t, title) } else { return false } }
        if !showing() {
            _ = open(chat: chat, folder: nil)
            for _ in 0..<60 where !showing() { Thread.sleep(forTimeInterval: 0.4) }
        }
        guard showing(), let app = NSRunningApplication.runningApplications(withBundleIdentifier: CursorApp.bundle).first else { return false }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 1)
        enableAccessibility(ax)
        let labels: Set<String> = allow ? ["Run \u{23CE}", "Run", "Allow", "Allow \u{23CE}", "Accept", "Approve"] : ["Skip", "Reject", "Deny"]
        for _ in 0..<10 {
            if let window = agentsWindow(ax),
               let button = ConductorApp.first(in: [window], limit: 4000, {
                   ConductorApp.attr($0, kAXRoleAttribute) as? String == "AXButton" && (ConductorApp.attr($0, kAXTitleAttribute) as? String).map(labels.contains) == true
               }) {
                return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return false
    }
}
