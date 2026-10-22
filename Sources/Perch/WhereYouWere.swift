import AppKit
import ApplicationServices

/// The app you were in and its window, taken before Perch has to bring another app forward (a reply it pastes, a session it
/// resumes in a new terminal tab), so it can put you back there once it is done. Perch itself never counts: when it is the
/// app in front (the shortcut can make it so as the card opens), the app you were in before it is the one.
struct WhereYouWere {
    let app: NSRunningApplication?
    let window: AXUIElement?

    /// The last app other than Perch to come forward, kept from launch (`watch`).
    @MainActor private static var lastOther: NSRunningApplication?
    @MainActor private static var watching: NSObjectProtocol?
    @MainActor static func watch() {
        guard watching == nil else { return }
        lastOther = NSWorkspace.shared.frontmostApplication.flatMap { $0.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : $0 }
        watching = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            MainActor.assumeIsolated { lastOther = app }
        }
    }

    @MainActor static func now() -> WhereYouWere {
        var app = NSWorkspace.shared.frontmostApplication
        if app?.bundleIdentifier == Bundle.main.bundleIdentifier, let other = lastOther, !other.isTerminated { app = other }
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
