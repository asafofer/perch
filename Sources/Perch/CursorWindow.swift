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
