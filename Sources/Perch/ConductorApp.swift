import AppKit
import ApplicationServices
import PerchCore

/// Conductor has no link that opens a workspace it already has (its `conductor://` links only start new ones), so Perch
/// goes through its window with Accessibility: every workspace in the sidebar is a link whose address ends in
/// `/workspace/<id>`, and the page itself carries the same address, which tells the workspace in front. A Conductor update
/// that changes its page can leave Pick up at "Conductor, brought forward".
enum ConductorApp {
    nonisolated static let bundle = "com.conductor.app"

    /// Conductor, started or brought forward (a closed window comes back). Call on the main thread.
    @MainActor static func bringForward() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return }
        let config = NSWorkspace.OpenConfiguration(); config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    /// Presses the workspace's link in the sidebar, waiting for the window when Conductor is still starting. A project
    /// folded shut in the sidebar hides its workspaces, so it is opened first. True once the link was pressed. Blocks.
    nonisolated static func open(workspace: String, project: String) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let deadline = Date().addingTimeInterval(12)
        var unfolded = false
        while Date() < deadline {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first {
                let ax = AXUIElementCreateApplication(app.processIdentifier)
                AXUIElementSetMessagingTimeout(ax, 1)
                // From the application, not its window: the page's own elements hang off the application.
                if let link = first(in: [ax], { role($0) == "AXLink" && address($0)?.hasSuffix("/workspace/" + workspace) == true }) {
                    return AXUIElementPerformAction(link, kAXPressAction as CFString) == .success
                }
                // The window is up (it has a sidebar) but this workspace is not listed: its project is folded shut.
                if !unfolded, first(in: [ax], { role($0) == "AXButton" && title($0) == "My workspaces" }) != nil {
                    unfolded = true
                    if let name = first(in: [ax], { role($0) == "AXStaticText" && title($0) == project }) { click(name) }
                }
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return false
    }

    /// The workspace Conductor's window shows, from the page's address. Runs off the main thread.
    nonisolated static func showingNow() -> ClaudeComposer.Showing {
        guard AXIsProcessTrusted(), let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else { return .unreadable }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 1)
        guard let page = first(in: [ax], limit: 400, { role($0) == "AXWebArea" }) else { return .unreadable }
        let parts = address(page)?.split(separator: "?").first?.split(separator: "/").map(String.init) ?? []
        guard let i = parts.lastIndex(of: "workspace"), parts.indices.contains(i + 1) else { return .none }
        return .session(parts[i + 1])
    }

    // MARK: Accessibility

    nonisolated private static func attr(_ e: AXUIElement, _ name: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
    }
    nonisolated private static func role(_ e: AXUIElement) -> String? { attr(e, kAXRoleAttribute) as? String }
    /// The element's own words: its title, else its value or description (a piece of text keeps them in any of the three).
    nonisolated private static func title(_ e: AXUIElement) -> String? {
        [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute].lazy.compactMap { attr(e, $0) as? String }.first { !$0.isEmpty }
    }
    nonisolated private static func address(_ e: AXUIElement) -> String? { (attr(e, kAXURLAttribute) as? URL)?.absoluteString }

    /// The first element in these trees, breadth first so a window's chrome is not walked before its sidebar, that matches.
    nonisolated private static func first(in roots: [AXUIElement], limit: Int = 1500, _ match: (AXUIElement) -> Bool) -> AXUIElement? {
        var queue = roots, seen = 0
        while !queue.isEmpty, seen < limit {
            let e = queue.removeFirst(); seen += 1
            if match(e) { return e }
            queue.append(contentsOf: (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [])
        }
        return nil
    }

    /// Clicks the middle of an element with the mouse, the pointer put back where it was. The project's row in the sidebar
    /// takes a click but offers no press action to Accessibility.
    @discardableResult nonisolated private static func click(_ e: AXUIElement) -> Bool {
        var pos = CGPoint.zero, size = CGSize.zero
        guard let p = attr(e, kAXPositionAttribute), let z = attr(e, kAXSizeAttribute),
              AXValueGetValue(p as! AXValue, .cgPoint, &pos), AXValueGetValue(z as! AXValue, .cgSize, &size), size.width > 0 else { return false }
        let at = CGPoint(x: pos.x + size.width / 2, y: pos.y + size.height / 2)
        let before = CGEvent(source: nil)?.location
        let src = CGEventSource(stateID: .combinedSessionState)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: at, mouseButton: .left)?.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.04)
        }
        if let before { CGWarpMouseCursorPosition(before) }
        return true
    }
}
