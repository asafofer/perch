import AppKit
import CoreGraphics

/// Fires once when you come back after being away. Reads the system idle counter, which needs no permission.
@MainActor
final class ActivityMonitor {
    /// Called with when you left: the last input before the break, or when the Mac went to sleep.
    var onReturn: ((Date?) -> Void)?
    private var awaySince: Date?
    var threshold: TimeInterval
    private var armed = false
    private var timer: Timer?
    private var asleepAt: Date?

    init(threshold: TimeInterval) {
        self.threshold = threshold
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // Sleep counts as being away only when it lasted as long as the idle threshold: closing the lid to change rooms is not a break.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.asleepAt = Date() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let t = self.asleepAt, Date().timeIntervalSince(t) >= self.threshold { self.armed = true; self.awaySince = self.awaySince ?? t }
                self.asleepAt = nil
            }
        }
    }

    /// The lock screen is up. Typing your password is input too, so returning waits until you are actually in.
    static var screenLocked: Bool {
        (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    private func tick() {
        if Self.screenLocked { return }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        if idle >= threshold { if !armed { awaySince = Date().addingTimeInterval(-idle) }; armed = true }
        else if armed && idle < 3 { armed = false; let since = awaySince; awaySince = nil; onReturn?(since) }
    }
}
