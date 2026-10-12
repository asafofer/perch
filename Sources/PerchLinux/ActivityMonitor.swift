import CPerchLinux
import Foundation

// OWNER: the input-and-desktop agent. STUB.
/// Fires once when you come back after being away (X screensaver idle time; a locked screen waits until unlocked).
@MainActor
final class ActivityMonitor {
    var onReturn: ((Date?) -> Void)?
    var threshold: TimeInterval
    init(threshold: TimeInterval) { self.threshold = threshold }
    /// Seconds since the last keyboard or mouse input.
    static func idleSeconds() -> TimeInterval { 0 }
}
