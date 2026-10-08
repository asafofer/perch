import AppKit
import CoreGraphics

/// Fires once when you come back after being away. Reads the system idle counter, which needs no permission.
@MainActor
final class ActivityMonitor {
    var onReturn: (() -> Void)?
    var threshold: TimeInterval
    private var armed = false
    private var timer: Timer?

    init(threshold: TimeInterval) {
        self.threshold = threshold
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.armed = true }
        }
    }

    private func tick() {
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        if idle >= threshold { armed = true }
        else if armed && idle < 3 { armed = false; onReturn?() }
    }
}
