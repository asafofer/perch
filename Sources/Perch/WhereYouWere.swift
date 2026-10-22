import AppKit
import ApplicationServices

/// The app you were in and its window, taken before Perch has to bring another app forward (a reply it pastes, a session it
/// resumes in a new terminal tab), so it can put you back there once it is done. Perch's own panel never counts: it does
/// not take the front when it opens.
struct WhereYouWere {
    let app: NSRunningApplication?
    let window: AXUIElement?

    static func now() -> WhereYouWere {
        let app = NSWorkspace.shared.frontmostApplication
        var window: AnyObject?
        if let app, AXIsProcessTrusted() {
            AXUIElementCopyAttributeValue(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedWindowAttribute as CFString, &window)
        }
        return WhereYouWere(app: app, window: window.map { $0 as! AXUIElement })
    }

    /// That window raised in front of the app's others, and the app back in front.
    func restore() {
        guard let app, !app.isTerminated, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        if let window {
            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }
        app.activate()
        if AXIsProcessTrusted() { AXUIElementSetAttributeValue(AXUIElementCreateApplication(app.processIdentifier), kAXFrontmostAttribute as CFString, kCFBooleanTrue) }
    }
}
