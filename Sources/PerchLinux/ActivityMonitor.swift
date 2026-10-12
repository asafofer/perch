import CPerchLinux
import Foundation

/// Fires once when you come back after being away. Reads X's idle counter (the XScreenSaver extension), which needs no
/// permission.
@MainActor
final class ActivityMonitor {
    /// Called with when you left: the last input before the break, or when the computer went to sleep.
    var onReturn: ((Date?) -> Void)?
    var threshold: TimeInterval
    private var awaySince: Date?
    private var armed = false
    private var asleepAt: Date?
    /// The last input before the screen locked, while it is locked.
    private var lockedSince: Date?

    init(threshold: TimeInterval) {
        self.threshold = threshold
        GLoop.every(2) { [weak self] in
            guard let self else { return false }
            self.tick(); return true
        }
        // Sleep counts as being away only when it lasted as long as the idle threshold: closing the lid to change rooms is
        // not a break. logind says so before the system sleeps (true) and after it wakes (false).
        DBus.subscribe(DBus.system, sender: "org.freedesktop.login1", iface: "org.freedesktop.login1.Manager", member: "PrepareForSleep",
                       path: "/org/freedesktop/login1") { [weak self] args in
            guard let self, let going = GV.bool(args, 0) else { return }
            if going { self.asleepAt = Date(); return }
            if let t = self.asleepAt, Date().timeIntervalSince(t) >= self.threshold { self.armed = true; self.awaySince = self.awaySince ?? t }
            self.asleepAt = nil
        }
    }

    /// Seconds since the last keyboard or mouse input, from the X server.
    static func idleSeconds() -> TimeInterval {
        guard let d = X11.display, let info = XScreenSaverAllocInfo() else { return 0 }
        defer { XFree(info) }
        guard XScreenSaverQueryInfo(d, X11.root, info) != 0 else { return 0 }
        return TimeInterval(info.pointee.idle) / 1000
    }

    /// The lock screen is up (as last read). Typing your password is input too, so returning waits until you are in.
    static var screenLocked: Bool { ScreenLock.locked }

    private func tick() {
        let idle = Self.idleSeconds()
        // Asking whether the screen is locked costs a few D-Bus calls, so only while you might be away or it was locked.
        if idle >= 5 || ScreenLock.locked { ScreenLock.refresh() }
        if ScreenLock.locked {
            if lockedSince == nil { lockedSince = Date().addingTimeInterval(-idle) }
            return
        }
        // A lock that lasted the threshold is a break, though unlocking was input: you come back with the next touch.
        if let t = lockedSince {
            lockedSince = nil
            if Date().timeIntervalSince(t) >= threshold { armed = true; awaySince = awaySince ?? t }
        }
        if idle >= threshold { if !armed { awaySince = Date().addingTimeInterval(-idle) }; armed = true }
        else if armed && idle < 3 { armed = false; let since = awaySince; awaySince = nil; onReturn?(since) }
    }
}

/// Whether the screen is locked, from whichever locker this desktop runs: logind's LockedHint (set by most lockers and
/// display managers), and the screensaver services that answer GetActive on the session bus (xfce4-screensaver,
/// light-locker and others as org.freedesktop.ScreenSaver, gnome-screensaver). Any one saying so counts. The readings
/// arrive a moment after `refresh()`; `locked` is the latest.
@MainActor
enum ScreenLock {
    private static var readings: [String: Bool] = [:]
    static var locked: Bool { readings.values.contains(true) }

    static func refresh() {
        DBus.property(DBus.system, "org.freedesktop.login1", "/org/freedesktop/login1/session/auto", "org.freedesktop.login1.Session", "LockedHint") { v in
            readings["logind"] = v.map { g_variant_get_boolean($0) != 0 } ?? false
        }
        for (name, path) in [("org.xfce.ScreenSaver", "/org/xfce/ScreenSaver"), ("org.freedesktop.ScreenSaver", "/org/freedesktop/ScreenSaver"),
                             ("org.gnome.ScreenSaver", "/org/gnome/ScreenSaver")] {
            DBus.call(DBus.session, name, path, name, "GetActive", timeout: 500) { reply in
                readings[name] = reply.flatMap { GV.bool($0, 0) } ?? false
            }
        }
    }
}
