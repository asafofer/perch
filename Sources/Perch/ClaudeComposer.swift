import AppKit
import ApplicationServices
import PerchCore

/// Answers a session in the Claude app without bringing the app forward, through Accessibility: Claude's window switches to
/// the session from its sidebar, the words go into the message field and Send is pressed, then the window goes back to what
/// it showed. A draft already in that field is set aside and put back after Send, so only the reply goes. Any step that does
/// not look exactly as expected gives up before anything is sent, and the caller pastes instead.
/// What it relies on in the app: the page's address ends in the session's id, sidebar rows carry the session's title, the
/// message field is a ProseMirror editor, and its Send button is labelled "Send".
enum ClaudeComposer {
    /// What happened: sent or not, the session Claude's window showed before (for a fallback to go back to), and whether
    /// its field held a draft (a fallback must then not press Return, or the draft would go too).
    struct Result { var sent: Bool; var shown: String?; var draft = false }

    /// Runs off the main thread: every step waits on the Claude app. `titles`: what its sidebar row may read.
    static func send(_ text: String, to id: String, titles: [String]) -> Result {
        guard AXIsProcessTrusted(), !text.isEmpty,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: Restorer.claudeApp).first else { return Result(sent: false, shown: nil) }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 1)
        // Electron leaves its web content out of the tree until an assistive app asks for it. The first time takes a moment.
        AXUIElementSetAttributeValue(ax, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        guard let page = wait(4, { page(in: ax) }) else { return fail("its window shows no Code page", nil) }

        let before = showing(page), beforeTitle = string(page, "AXTitle").removingSuffix(" - Claude Code")
        var fail = { (why: String) in Self.fail(why, before) }
        var moved = false
        defer {
            // Back to the session it showed, so nothing in Claude's window looks different.
            if moved, let before, !beforeTitle.isEmpty, before != id { _ = open(before, titles: [beforeTitle], in: page) }
        }
        if before != id {
            guard open(id, titles: titles, in: page) else { return fail("no sidebar row for the session") }
            moved = true
        }
        guard let field = wait(2, { composer(in: page) }) else { return fail("no message field") }
        // Something you started typing there is set aside, so only the reply is sent, and goes back once it has.
        let draft = value(field)
        fail = { (why: String) in Result(sent: false, shown: before, draft: !draft.isBlank).logged(why) }
        if !draft.isBlank {
            AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, "" as CFString)
            guard wait(1, { value(field).isBlank ? true : nil }) != nil else { putBack(draft, in: page); return fail("its draft would not clear") }
        }
        AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, text as CFString)
        let send = wait(1) { () -> AXUIElement? in
            guard let b = sendButton(near: field), (attr(b, kAXEnabledAttribute) as? Bool) == true else { return nil }
            return b
        }
        // The field must hold exactly these words, in this session, before Send.
        guard let send, showing(page) == id, value(field).trimmed == text.trimmed else {
            AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, draft as CFString)
            return fail("the words did not land in the field")
        }
        guard AXUIElementPerformAction(send, kAXPressAction as CFString) == .success else {
            AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, draft as CFString)
            return fail("Send did not press")
        }
        // Sent once the field empties; going back before that could leave the words behind.
        if wait(2, { value(field).isBlank ? true : nil }) == nil { NSLog("Perch: Claude's field still holds the reply after Send") }
        if !draft.isBlank { putBack(draft, in: page) }
        NSLog("Perch: sent reply into Claude in the background")
        return Result(sent: true, shown: before)
    }

    /// Your draft back in the field, as it was. The field may have been drawn anew after Send, so it is looked up again.
    private static func putBack(_ draft: String, in page: AXUIElement) {
        guard let field = wait(1, { composer(in: page) }) else { NSLog("Perch: could not put Claude's draft back"); return }
        AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, draft as CFString)
        if value(field).trimmed != draft.trimmed { NSLog("Perch: Claude's draft did not come back as it was") }
    }

    private static func fail(_ why: String, _ shown: String?) -> Result { Result(sent: false, shown: shown).logged(why) }

    /// What the Claude app's window shows now, for telling the session you are in. Runs off the main thread.
    enum Showing: Equatable { case session(String), none, unreadable }
    static func showingNow() -> Showing {
        guard AXIsProcessTrusted(), let app = NSRunningApplication.runningApplications(withBundleIdentifier: Restorer.claudeApp).first else { return .unreadable }
        // Walking Claude's window is the costly part, so the page it found is kept and only its address is read again.
        if let (pid, page) = cachedPage, pid == app.processIdentifier, url(page) != nil { return showing(page).map { .session($0) } ?? .none }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 1)
        AXUIElementSetAttributeValue(ax, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        guard let page = page(in: ax) else { cachedPage = nil; return .unreadable }
        cachedPage = (app.processIdentifier, page)
        return showing(page).map { .session($0) } ?? .none
    }
    nonisolated(unsafe) private static var cachedPage: (pid: pid_t, page: AXUIElement)?

    // MARK: the page

    /// Claude's Code page: the web area whose address is on claude.ai/epitaxy.
    private static func page(in app: AXUIElement) -> AXUIElement? {
        for w in (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? [] {
            if let p = first(in: w, limit: 400, { role($0) == "AXWebArea" && (url($0)?.path.hasPrefix("/epitaxy") ?? false) }) { return p }
        }
        return nil
    }
    /// The session the page shows ("local_…"), from its address.
    private static func showing(_ page: AXUIElement) -> String? {
        guard let last = url(page)?.lastPathComponent, last.hasPrefix("local_") || last.hasPrefix("session_") else { return nil }
        return last
    }
    /// Presses the session's sidebar row and waits for the page to show it. Rows with the same title are tried in turn.
    private static func open(_ id: String, titles: [String], in page: AXUIElement) -> Bool {
        let bar = first(in: page, limit: 400, { classes($0).contains("dframe-sidebar") }) ?? page
        let rows = all(in: bar, { e in
            role(e) == "AXButton" && titles.contains { t in first(in: e, limit: 12, { role($0) == "AXStaticText" && value($0) == t }) != nil }
        })
        for row in rows.prefix(3) {
            guard AXUIElementPerformAction(row, kAXPressAction as CFString) == .success else { continue }
            if wait(3, { showing(page) == id ? true : nil }) != nil { return true }
        }
        return false
    }
    /// The message field of the pane the address belongs to.
    private static func composer(in page: AXUIElement) -> AXUIElement? {
        let pane = first(in: page, { classes($0).contains("dframe-pane-primary") }) ?? page
        let fields = all(in: pane, { role($0) == "AXTextArea" && classes($0).contains("ProseMirror") })
        return fields.count == 1 ? fields[0] : nil
    }
    /// Send sits beside the field, a few levels up.
    private static func sendButton(near field: AXUIElement) -> AXUIElement? {
        var box = field
        for _ in 0..<5 { guard let up = attr(box, kAXParentAttribute) else { break }; box = up as! AXUIElement }
        return first(in: box, limit: 200, { role($0) == "AXButton" && string($0, kAXDescriptionAttribute) == "Send" })
    }

    // MARK: reading the tree

    private static func attr(_ e: AXUIElement, _ name: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
    }
    private static func string(_ e: AXUIElement, _ name: String) -> String { attr(e, name) as? String ?? "" }
    private static func role(_ e: AXUIElement) -> String { string(e, kAXRoleAttribute) }
    private static func value(_ e: AXUIElement) -> String { string(e, kAXValueAttribute) }
    private static func url(_ e: AXUIElement) -> URL? { attr(e, kAXURLAttribute) as? URL }
    private static func classes(_ e: AXUIElement) -> [String] { attr(e, "AXDOMClassList") as? [String] ?? [] }

    /// Depth first, visiting at most `limit` elements: a long conversation is a big tree.
    private static func all(in root: AXUIElement, limit: Int = 6000, stopAtFirst: Bool = false, _ match: (AXUIElement) -> Bool) -> [AXUIElement] {
        var out: [AXUIElement] = [], stack = [root], seen = 0
        while let e = stack.popLast(), seen < limit {
            seen += 1
            if match(e) { out.append(e); if stopAtFirst { break } }
            stack.append(contentsOf: ((attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? []).reversed())
        }
        return out
    }
    private static func first(in root: AXUIElement, limit: Int = 6000, _ match: (AXUIElement) -> Bool) -> AXUIElement? {
        all(in: root, limit: limit, stopAtFirst: true, match).first
    }
    private static func wait<T>(_ seconds: Double, _ check: () -> T?) -> T? {
        let end = Date().addingTimeInterval(seconds)
        repeat {
            if let v = check() { return v }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < end
        return nil
    }
}

/// Rename, archive or delete a session of the Claude app through its own sidebar menu. The app builds that menu only while it is
/// the active app (tried with it hidden behind another: the call succeeds and nothing shows), so Claude comes forward for the
/// moment it takes, and what was in front before it comes back. A step that does not look as expected gives up before the next.
extension ClaudeComposer {
    static func manage(_ a: ManageAction, session id: String, titles: [String], name: String?) -> Swift.Result<Void, SessionManager.Failure> {
        func fail(_ why: String) -> Swift.Result<Void, SessionManager.Failure> { .failure(.init(why: why)) }
        guard AXIsProcessTrusted() else { return fail("Perch needs Accessibility to use the Claude app's menu") }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: Restorer.claudeApp).first else { return fail("the Claude app is not open") }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 1)
        AXUIElementSetAttributeValue(ax, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        guard let page = wait(4, { page(in: ax) }) else { return fail("its window shows no Code page") }
        let was = NSWorkspace.shared.frontmostApplication
        let wasShowing = showing(page), wasTitle = string(page, "AXTitle").removingSuffix(" - Claude Code")
        if !app.isActive {
            app.activate()
            guard wait(3, { app.isActive ? true : nil }) != nil else { return fail("the Claude app would not come forward") }
        }
        defer { if let was, was != app, !was.isTerminated { was.activate() } }
        guard let row = wait(3, { sidebarRow(titles: titles, in: page) }) else { return fail("no sidebar row for the session") }
        guard AXUIElementPerformAction(row, "AXShowMenu" as CFString) == .success,
              let menu = wait(2, { rowMenu(in: ax) }) else { return fail("its row menu did not open") }
        let want = a == .rename ? "Rename" : a == .archive ? "Archive" : "Delete"
        guard let item = (attr(menu, kAXChildrenAttribute) as? [AXUIElement])?.first(where: { string($0, kAXTitleAttribute) == want }) else {
            _ = AXUIElementPerformAction(menu, kAXCancelAction as CFString); return fail("the row menu has no \(want)")
        }
        guard AXUIElementPerformAction(item, kAXPressAction as CFString) == .success else { return fail("\(want) did not press") }
        switch a {
        case .rename:
            guard let name, !name.isEmpty else { return fail("no name") }
            // The row's title becomes a field with the title in it, focused.
            guard let field = wait(2, { editField(in: ax, titles: titles) }) else { return fail("no field to rename in") }
            AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, name as CFString)
            guard value(field) == name else { return fail("the name did not land in the field") }
            if AXUIElementPerformAction(field, kAXConfirmAction as CFString) != .success { pressReturn() }
            guard wait(3, { sidebarRow(titles: [name], in: page) }) != nil else { return fail("the app did not take the new name") }
        case .archive:
            guard wait(3, { sidebarRow(titles: titles, in: page) == nil ? true : nil }) != nil else { return fail("the session is still in the list") }
        case .delete:
            // The app asks once more: its confirming button.
            if let ok = wait(2, { confirmButton(in: ax) }) { _ = AXUIElementPerformAction(ok, kAXPressAction as CFString) }
            guard wait(4, { sidebarRow(titles: titles, in: page) == nil ? true : nil }) != nil else { return fail("the session is still in the list") }
        }
        // The window shows what it showed before.
        if let wasShowing, !wasTitle.isEmpty, wasShowing != id, let back = sidebarRow(titles: [wasTitle], in: page) { _ = AXUIElementPerformAction(back, kAXPressAction as CFString) }
        return .success(())
    }

    /// A sidebar row by its title: a button holding that text.
    private static func sidebarRow(titles: [String], in page: AXUIElement) -> AXUIElement? {
        let bar = first(in: page, limit: 400, { classes($0).contains("dframe-sidebar") }) ?? page
        return all(in: bar, stopAtFirst: true) { e in
            role(e) == "AXButton" && titles.contains { t in string(e, kAXTitleAttribute).hasPrefix(t) || first(in: e, limit: 12, { role($0) == "AXStaticText" && value($0) == t }) != nil }
        }.first
    }
    /// The row menu is the one that has Archive in it.
    private static func rowMenu(in app: AXUIElement) -> AXUIElement? {
        first(in: app, limit: 3000, { e in
            role(e) == "AXMenu" && ((attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? []).contains { string($0, kAXTitleAttribute) == "Archive" }
        })
    }
    /// The field Rename opens: it holds the session's current title.
    private static func editField(in app: AXUIElement, titles: [String]) -> AXUIElement? {
        first(in: app, limit: 3000, { e in
            let r = role(e)
            return (r == "AXTextField" || r == "AXTextArea") && titles.contains { value(e).hasPrefix($0) }
        })
    }
    /// The confirming button of the question Delete asks.
    private static func confirmButton(in app: AXUIElement) -> AXUIElement? {
        first(in: app, limit: 3000, { e in
            role(e) == "AXButton" && string(e, kAXTitleAttribute) == "Delete" && !classes(e).contains("dframe-sidebar")
        })
    }
    private static func pressReturn() {
        for down in [true, false] { CGEvent(keyboardEventSource: CGEventSource(stateID: .hidSystemState), virtualKey: 36, keyDown: down)?.post(tap: .cghidEventTap) }
    }
}

private extension ClaudeComposer.Result {
    func logged(_ why: String) -> Self { NSLog("Perch: background reply gave up (\(why))"); return self }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var isBlank: Bool { trimmed.isEmpty }
    func removingSuffix(_ s: String) -> String { hasSuffix(s) ? String(dropLast(s.count)) : self }
}
