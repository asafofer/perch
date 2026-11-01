import AppKit
import ApplicationServices
import PerchCore

/// Grok Bot keeps whether a bot is at work in memory only; its window's sidebar is the one place on this Mac that says it.
/// Read through Accessibility, as Perch reads Cursor's window: nothing is pressed.
enum GrokBotWindow {
    nonisolated static let bundle = "com.anysphere.sand"

    /// The names of the bot buttons in Grok Bot's sidebar ("X Growth, Working"). Empty when Grok Bot is not running, its window
    /// is closed, or Perch has no Accessibility. A read cut short by its time or size limit keeps the last whole one, for up
    /// to half a minute, so a bot it did not reach is not taken for done. Blocks for a moment.
    nonisolated static func sidebar() -> [String] {
        let now = Date()
        if let read = read() { lock.lock(); last = (read, now); lock.unlock(); return read }
        lock.lock(); defer { lock.unlock() }
        return now.timeIntervalSince(last.at) < 30 ? last.names : []
    }
    nonisolated(unsafe) private static var last: (names: [String], at: Date) = ([], .distantPast)
    private static let lock = NSLock()

    /// The sidebar's bot buttons, or nil when the read stopped before it was done.
    nonisolated private static func read() -> [String]? {
        guard AXIsProcessTrusted(), let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else { return [] }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 0.5)
        // A timeout holds only for the element it is set on, so each one gets it, and the whole read stops after a second.
        let deadline = Date().addingTimeInterval(1)
        // Electron builds its tree only once asked, and asking again restarts it, so only while it is not on.
        if ConductorApp.attr(ax, "AXManualAccessibility") as? Bool != true {
            AXUIElementSetAttributeValue(ax, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }
        // Breadth first, and never into a chat, which can hold hundreds of elements.
        var queue = [ax], seen = 0
        while !queue.isEmpty {
            guard seen < 400, Date() < deadline else { return nil }
            let e = queue.removeFirst(); seen += 1
            AXUIElementSetMessagingTimeout(e, 0.25)
            let name = label(e)
            if name == "Bot list" { return buttons(in: e, until: deadline) }
            if name == "Conversation transcript" { continue }
            guard let kids = children(e) else { return nil }
            queue.append(contentsOf: kids)
        }
        return []
    }

    nonisolated private static func buttons(in list: AXUIElement, until deadline: Date) -> [String]? {
        var out: [String] = [], queue = [list], seen = 0
        while !queue.isEmpty {
            guard seen < 300, Date() < deadline else { return nil }
            let e = queue.removeFirst(); seen += 1
            AXUIElementSetMessagingTimeout(e, 0.25)
            if ConductorApp.attr(e, kAXRoleAttribute) as? String == "AXButton" { if let name = label(e) { out.append(name) }; continue }
            guard let kids = children(e) else { return nil }
            queue.append(contentsOf: kids)
        }
        return out
    }

    /// An element's children: none when it has none (no value, or no such attribute), nil for any other failure, such as
    /// Grok Bot not answering in time or the element going away (the read is then not whole).
    nonisolated private static func children(_ e: AXUIElement) -> [AXUIElement]? {
        var v: AnyObject?
        switch AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &v) {
        case .success: return v as? [AXUIElement]
        case .noValue, .attributeUnsupported: return []
        default: return nil
        }
    }

    /// Presses a choice of a bot's open question in Grok Bot's window, Grok Bot left behind the app you are in, which answers
    /// it as a click there would. When another bot shows, this one is chosen in the sidebar first and that one again after.
    /// Nothing is pressed unless the window's heading names the bot (a name two bots share is never chosen) and a button with
    /// the choice's words sits under the question's words. False when nothing was pressed. Blocks for up to a few seconds.
    nonisolated static func answer(bot: String, question: String, choice: String) -> Bool {
        guard AXIsProcessTrusted(), let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else { return false }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 1)
        if ConductorApp.attr(ax, "AXManualAccessibility") as? Bool != true {
            AXUIElementSetAttributeValue(ax, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }
        func role(_ e: AXUIElement) -> String? { ConductorApp.attr(e, kAXRoleAttribute) as? String }
        func heading() -> String? { ConductorApp.first(in: [ax]) { role($0) == "AXHeading" }.flatMap(label) }
        func button(of name: String) -> AXUIElement? {
            guard let list = ConductorApp.first(in: [ax], { label($0) == "Bot list" }) else { return nil }
            let hits = all(in: list) { role($0) == "AXButton" && GrokBotStore.name(ofSidebar: label($0) ?? "") == name }
            return hits.count == 1 ? hits[0] : nil
        }
        func press(_ e: AXUIElement) -> Bool { AXUIElementPerformAction(e, kAXPressAction as CFString) == .success }
        func waitFor(_ seconds: Double, _ ok: () -> Bool) -> Bool {
            let end = Date().addingTimeInterval(seconds)
            while Date() < end { if ok() { return true }; Thread.sleep(forTimeInterval: 0.15) }
            return ok()
        }
        let shown = heading()
        var back: AXUIElement?
        if shown != bot {
            guard let b = button(of: bot), press(b) else { return false }
            back = shown.flatMap(button(of:))
        }
        defer { if let back { _ = press(back) } }
        guard waitFor(3, { heading() == bot }) else { return false }
        // The newest question with these words: an older one asked the same way has already been answered.
        var pick: AXUIElement?
        _ = waitFor(2) {
            let asked = all(in: ax, limit: 4000) { role($0) == "AXGroup" && label($0) == question }
            pick = asked.last.flatMap { q in all(in: q) { role($0) == "AXButton" && label($0) == choice }.first }
            return pick != nil
        }
        return pick.map(press) ?? false
    }

    /// Every element in this tree, breadth first, that matches.
    nonisolated private static func all(in root: AXUIElement, limit: Int = 600, _ match: (AXUIElement) -> Bool) -> [AXUIElement] {
        var out: [AXUIElement] = [], queue = [root], seen = 0
        while !queue.isEmpty, seen < limit {
            let e = queue.removeFirst(); seen += 1
            if match(e) { out.append(e) }
            queue.append(contentsOf: (ConductorApp.attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [])
        }
        return out
    }

    nonisolated private static func label(_ e: AXUIElement) -> String? {
        [kAXTitleAttribute, kAXDescriptionAttribute].lazy.compactMap { ConductorApp.attr(e, $0) as? String }.first { !$0.isEmpty }
    }
}
