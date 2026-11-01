import AppKit
import ApplicationServices

/// Grok Bot keeps whether a bot is at work in memory only; its window's sidebar is the one place on this Mac that says it.
/// Read through Accessibility, as Perch reads Cursor's window: nothing is pressed.
enum GrokBotWindow {
    nonisolated static let bundle = "com.anysphere.sand"

    /// The names of the bot buttons in Grok Bot's sidebar ("X Growth, Working"). Empty when Grok Bot is not running, its window
    /// is closed, or Perch has no Accessibility. Blocks for a moment.
    nonisolated static func sidebar() -> [String] {
        guard AXIsProcessTrusted(), let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else { return [] }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 0.5)
        // Electron builds its tree only once asked, and asking again restarts it, so only while it is not on.
        if ConductorApp.attr(ax, "AXManualAccessibility") as? Bool != true {
            AXUIElementSetAttributeValue(ax, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }
        // Breadth first, and never into a chat, which can hold hundreds of elements.
        var queue = [ax], seen = 0
        while !queue.isEmpty, seen < 400 {
            let e = queue.removeFirst(); seen += 1
            let name = label(e)
            if name == "Bot list" { return buttons(in: e) }
            if name == "Conversation transcript" { continue }
            queue.append(contentsOf: (ConductorApp.attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [])
        }
        return []
    }

    nonisolated private static func buttons(in list: AXUIElement) -> [String] {
        var out: [String] = [], queue = [list], seen = 0
        while !queue.isEmpty, seen < 300 {
            let e = queue.removeFirst(); seen += 1
            if ConductorApp.attr(e, kAXRoleAttribute) as? String == "AXButton" { if let name = label(e) { out.append(name) }; continue }
            queue.append(contentsOf: (ConductorApp.attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [])
        }
        return out
    }

    nonisolated private static func label(_ e: AXUIElement) -> String? {
        [kAXTitleAttribute, kAXDescriptionAttribute].lazy.compactMap { ConductorApp.attr(e, $0) as? String }.first { !$0.isEmpty }
    }
}
