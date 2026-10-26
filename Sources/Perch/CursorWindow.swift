import AppKit
import PerchCore

/// Going back to a Cursor chat. Cursor's own link opens an existing chat in its Agents window and puts the cursor in its
/// prompt: `cursor://anysphere.cursor-deeplink/agent?id=<chat id>` (the id of the transcript). Without a chat id, or when
/// Cursor is not installed, the chat's folder opens instead.
enum CursorWindow {
    static func trace(_ s: String) { if ProcessInfo.processInfo.environment["PERCH_TRACE"] != nil { NSLog("Perch cursor: %@", s) } }
    static var appURL: URL? { AppIcons.url("cursor") }

    /// The title Cursor shows for a chat: the row's title, which a chat with no folder carries as its name instead.
    static func title(of p: Project) -> String { p.topic.isEmpty ? p.name : p.topic }

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

    /// Whether the window's chat title is the one wanted: the same words, or (the row clips a long title with an ellipsis) the
    /// start of it. Never a title that merely begins the same, since an answer is pressed in whichever chat this says it is.
    nonisolated static func matches(_ shown: String, _ want: String) -> Bool {
        if shown == want { return true }
        return want.hasSuffix("\u{2026}") && shown.hasPrefix(String(want.dropLast()))
    }

    /// Calls `done` every `interval` seconds, at most `tries` times, and stops at the first yes (a `for … where` would go on reading
    /// Cursor's windows for every try that is left).
    nonisolated static func wait(_ tries: Int, _ interval: TimeInterval, until done: () -> Bool) {
        for _ in 0..<tries {
            if done() { return }
            Thread.sleep(forTimeInterval: interval)
        }
    }

    /// The id of the chat the Agents window shows, as Cursor last saved it (`cursor/glass.selectedAgent`).
    nonisolated static func selectedChatId() -> String? { CursorStore(user: CursorApp.userDirectory)?.selectedChat() }

    /// Whether the window shows exactly this chat. A title does not name a chat (two can share one) and a button is pressed in
    /// whichever chat the window shows, so Cursor's own saved selection must name this chat's id, and the window's title agrees.
    nonisolated static func confirmed(chat: String, title: String) -> Bool {
        guard selectedChatId() == chat, case .session(let t) = showingNow() else { return false }
        return matches(t, title)
    }

    /// Chooses the chat in the sidebar: each row with its title is pressed in turn until Cursor says it is this chat. False when
    /// none does (the row is not in the sidebar, or the sidebar is hidden).
    nonisolated static func choose(_ ax: AXUIElement, chat: String, title: String) -> Bool {
        for row in sidebarRows(ax, title: title) {
            guard AXUIElementPerformAction(row, kAXPressAction as CFString) == .success else { continue }
            for _ in 0..<15 {
                if confirmed(chat: chat, title: title) { return true }
                Thread.sleep(forTimeInterval: 0.2)
            }
        }
        return false
    }

    /// Answers what Cursor asks in the chat: the chat is chosen in the Agents window's sidebar (or opened with its link, which
    /// names it by id, when Cursor is not running or the sidebar cannot), then the button of its prompt is pressed ("Run", or
    /// "Skip" to refuse), which Cursor shows in the chat itself. Nothing is pressed unless Cursor's saved selection names this chat.
    /// Cursor's own hooks cannot answer it (they run for every command, ones Cursor runs unasked too). Blocks: call it off the main thread.
    nonisolated static func answer(chat: String, title: String, allow: Bool) -> Bool {
        guard AXIsProcessTrusted(), link(chat: chat) != nil else { return false }
        var viaLink = false
        func viaTheLink() {
            viaLink = true
            _ = open(chat: chat, folder: nil)
            wait(60, 0.4) { confirmed(chat: chat, title: title) }
        }
        if NSRunningApplication.runningApplications(withBundleIdentifier: CursorApp.bundle).isEmpty { viaTheLink() }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: CursorApp.bundle).first else { return false }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 1)
        enableAccessibility(ax)
        var before: String?
        if !confirmed(chat: chat, title: title) {
            if case .session(let t) = showingNow() { before = t }
            if !choose(ax, chat: chat, title: title) { before = nil; viaTheLink() }
        }
        trace("answering \(allow ? "yes" : "no") for \(title): \(viaLink ? "opened by its link" : "chosen in the sidebar")")
        guard confirmed(chat: chat, title: title) else { return false }
        defer { if let before { _ = selectInSidebar(ax, title: before) } }
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

extension CursorWindow {
    /// The chats' rows in the Agents window's sidebar with this title (a button named by it, clipped long titles by their start).
    nonisolated static func sidebarRows(_ ax: AXUIElement, title: String) -> [AXUIElement] {
        guard let window = agentsWindow(ax) else { return [] }
        var queue = [window], rows: [AXUIElement] = [], seen = 0
        while !queue.isEmpty, seen < 6000 {
            let e = queue.removeFirst(); seen += 1
            if ConductorApp.attr(e, kAXRoleAttribute) as? String == "AXButton", let t = ConductorApp.attr(e, kAXTitleAttribute) as? String,
               !t.hasPrefix("Chat title."), matches(t, title),
               (ConductorApp.attr(e, "AXDOMClassList") as? [String])?.contains("ui-sidebar-menu-button-trigger") == true { rows.append(e) }
            queue.append(contentsOf: (ConductorApp.attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [])
        }
        return rows
    }

    /// Presses a chat's row in the Agents window's sidebar by its title (to put back the chat the window showed). False when it finds none.
    nonisolated static func selectInSidebar(_ ax: AXUIElement, title: String) -> Bool {
        guard let row = sidebarRows(ax, title: title).first else { return false }
        return AXUIElementPerformAction(row, kAXPressAction as CFString) == .success
    }
}

extension CursorWindow {
    /// `.unsure`: the words may be in the prompt and could not be taken out, so nothing may paste or send them again.
    enum Replied { case sent, draft, failed, unsure }

    /// Takes the words out of the prompt and reads it back: whether it is empty now.
    nonisolated private static func clear(_ prompt: AXUIElement) -> Bool {
        _ = AXUIElementSetAttributeValue(prompt, kAXValueAttribute as CFString, "" as CFString)
        Thread.sleep(forTimeInterval: 0.3)
        return (ConductorApp.attr(prompt, kAXValueAttribute) as? String ?? "x").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Replies in the chat without coming forward: the chat is chosen in the Agents window's sidebar, the words are set in its
    /// prompt through Accessibility (the field is writable, and Cursor's editor takes them like typed text) and its Send
    /// button is pressed; the chat the window showed is chosen again afterwards. Nothing is written unless Cursor's saved
    /// selection names this chat. `.draft` when something is already written there (nothing is touched), `.failed` when a step
    /// could not be done before anything was sent (Cursor not running, no such row, no button), `.unsure` when the words may
    /// be stuck in the prompt. Blocks: call it off the main thread.
    nonisolated static func reply(_ text: String, chat: String, title: String) -> Replied {
        guard AXIsProcessTrusted(), let app = NSRunningApplication.runningApplications(withBundleIdentifier: CursorApp.bundle).first else { return .failed }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 1)
        enableAccessibility(ax)
        var before: String?
        if !confirmed(chat: chat, title: title) {
            if case .session(let t) = showingNow() { before = t }
            guard choose(ax, chat: chat, title: title) else {
                // A wrong row may be showing now: put back what was.
                if let before { _ = selectInSidebar(ax, title: before) }
                return .failed
            }
        }
        defer { if let before { _ = selectInSidebar(ax, title: before) } }
        guard let window = agentsWindow(ax),
              let prompt = ConductorApp.first(in: [window], limit: 4000, {
                  ConductorApp.attr($0, kAXRoleAttribute) as? String == "AXTextArea" && ConductorApp.attr($0, kAXDescriptionAttribute) as? String == "Prompt"
              }) else { return .failed }
        let written = (ConductorApp.attr(prompt, kAXValueAttribute) as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard written.isEmpty else { return .draft }
        guard AXUIElementSetAttributeValue(prompt, kAXValueAttribute as CFString, text as CFString) == .success else { return clear(prompt) ? .failed : .unsure }
        // The Send button shows once the editor has taken the words.
        for _ in 0..<15 {
            if let button = ConductorApp.first(in: [window], limit: 4000, {
                ConductorApp.attr($0, kAXRoleAttribute) as? String == "AXButton" && ConductorApp.attr($0, kAXDescriptionAttribute) as? String == "Send message"
            }) {
                let ok = AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
                trace("reply \(ok ? "sent" : "not sent") in \(title), chosen in the sidebar")
                if ok { return .sent }
                // An error after the press does not say Cursor ignored it. Words gone from the prompt were sent (the fallback would
                // send them twice); words still there are taken back out, and only when that is confirmed may the fallback send them.
                Thread.sleep(forTimeInterval: 0.5)
                let left = (ConductorApp.attr(prompt, kAXValueAttribute) as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if left.isEmpty { return .sent }
                return clear(prompt) ? .failed : .unsure
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        // Nothing to send with: take the words back out so no stray text is left in the field.
        return clear(prompt) ? .failed : .unsure
    }
}
