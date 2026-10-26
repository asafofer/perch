import AppKit
import PerchCore

/// Going back to a Cursor chat. Cursor's own link opens an existing chat in its Agents window and puts the cursor in its
/// prompt: `cursor://anysphere.cursor-deeplink/agent?id=<chat id>` (the id of the transcript). Without a chat id, or when
/// Cursor is not installed, the chat's folder opens instead.
enum CursorWindow {
    static var appURL: URL? { AppIcons.url("cursor") }

    static func link(chat id: String) -> URL? {
        var parts = URLComponents(string: "cursor://anysphere.cursor-deeplink/agent")
        parts?.queryItems = [URLQueryItem(name: "id", value: id)]
        return parts?.url
    }

    /// Whether the chat was opened by its own link (the prompt then belongs to it, so a reply can be pasted).
    @discardableResult static func open(chat id: String?, folder: String?) -> Bool {
        guard let app = appURL else { return false }
        if let id, let url = link(chat: id) { NSWorkspace.shared.open(url); return true }
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
        AXUIElementSetAttributeValue(ax, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        guard let window = ConductorApp.attr(ax, kAXFocusedWindowAttribute) as! AXUIElement?,
              let page = ConductorApp.first(in: [window], limit: 400, { ConductorApp.attr($0, kAXRoleAttribute) as? String == "AXWebArea" }),
              (ConductorApp.attr(page, kAXTitleAttribute) as? String)?.contains("Agents") == true else { return .unreadable }
        let mark = "Chat title. "
        let hit = ConductorApp.first(in: [page], limit: 3000) {
            ConductorApp.attr($0, kAXRoleAttribute) as? String == "AXButton" && (ConductorApp.attr($0, kAXTitleAttribute) as? String)?.hasPrefix(mark) == true
        }
        guard let title = (hit.flatMap { ConductorApp.attr($0, kAXTitleAttribute) as? String })?.dropFirst(mark.count), !title.isEmpty else { return .none }
        return .session(String(title))
    }
}

extension CursorWindow {
    /// Whether the window's chat title is the one wanted. A title longer than the row's is clipped there.
    nonisolated static func matches(_ shown: String, _ want: String) -> Bool { shown == want || shown.hasPrefix(want) || want.hasPrefix(shown) }

    /// Answers what Cursor asks in the chat: opens the chat with its link, then presses the button of its prompt ("Run", or
    /// "Skip" to refuse), which Cursor shows in the chat itself. Nothing is pressed unless the window shows this very chat.
    /// Cursor's own hooks cannot answer it (they run for every command, ones Cursor runs unasked too). Blocks: call it off the main thread.
    nonisolated static func answer(chat: String, title: String, allow: Bool) -> Bool {
        guard AXIsProcessTrusted(), let url = link(chat: chat) else { return false }
        func showing() -> Bool { if case .session(let t) = showingNow() { return matches(t, title) } else { return false } }
        if !showing() {
            NSWorkspace.shared.open(url)
            for _ in 0..<25 where !showing() { Thread.sleep(forTimeInterval: 0.3) }
        }
        guard showing(), let app = NSRunningApplication.runningApplications(withBundleIdentifier: CursorApp.bundle).first else { return false }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 1)
        let labels: Set<String> = allow ? ["Run \u{23CE}", "Run", "Allow", "Allow \u{23CE}", "Accept", "Approve"] : ["Skip", "Reject", "Deny"]
        for _ in 0..<10 {
            if let window = ConductorApp.attr(ax, kAXFocusedWindowAttribute) as! AXUIElement?,
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
