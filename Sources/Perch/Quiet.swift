import AppKit
import CoreAudio
import CoreMediaIO

/// Moments when Perch must not speak up on its own: a call, the camera on, a presentation on screen, a launcher open.
/// Hover and the shortcuts still work; only the proactive card waits.
enum Quiet {
    /// Dictation apps open the mic for a moment while you talk to them. That is not a call.
    private static let dictation = ["wispr", "handy", "superwhisper", "macwhisper", "voiceink", "aqua", "speechrecognition", "dictation"]
    private static let presenters: Set<String> = ["com.apple.iWork.Keynote", "com.microsoft.Powerpoint"]

    /// Why Perch should wait, or nil when it is fine to show the card.
    static func reason() -> String? {
        if let app = appUsingMic() { return "the mic is in use by \(app)" }
        if cameraInUse() { return "the camera is on" }
        if presenting() { return "a presentation is on screen" }
        if let app = launcherOpen() { return "\(app) has the keyboard" }
        return nil
    }

    /// A launcher has the keyboard (Raycast, Spotlight, Alfred): it types into a panel of an app that is not the one in
    /// front. Perch's card would cover it. Needs Accessibility; without it, or when the system does not say, nothing counts.
    static func launcherOpen() -> String? {
        guard AXIsProcessTrusted() else { return nil }
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedApplicationAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(focused as! AXUIElement, &pid) == .success, pid != ProcessInfo.processInfo.processIdentifier,
              let front = NSWorkspace.shared.frontmostApplication, pid != front.processIdentifier else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid \(pid)"
    }

    /// The first app recording from any microphone, per process, so an idle headset that is merely open does not count.
    static func appUsingMic() -> String? {
        let me = ProcessInfo.processInfo.processIdentifier
        for process in objects(kAudioHardwarePropertyProcessObjectList) {
            var running: UInt32 = 0
            guard read(process, kAudioProcessPropertyIsRunningInput, &running), running != 0 else { continue }
            var pid: pid_t = 0
            _ = read(process, kAudioProcessPropertyPID, &pid)
            guard pid != me else { continue }
            var bundle: Unmanaged<CFString>?
            _ = read(process, kAudioProcessPropertyBundleID, &bundle)
            let id = (bundle?.takeRetainedValue() as String?) ?? NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "pid \(pid)"
            if dictation.contains(where: { id.lowercased().contains($0) }) { continue }
            return NSRunningApplication(processIdentifier: pid)?.localizedName ?? id
        }
        return nil
    }

    static func cameraInUse() -> Bool {
        var address = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size) == noErr, size > 0 else { return false }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &used, &devices) == noErr else { return false }
        for device in devices {
            var running: UInt32 = 0, got: UInt32 = 0
            var a = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                                              mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                                              mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
            if CMIOObjectGetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &got, &running) == noErr, running != 0 { return true }
        }
        return false
    }

    /// Keynote or PowerPoint in front with a window covering a whole display: a slideshow.
    static func presenting() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication, presenters.contains(front.bundleIdentifier ?? "") else { return false }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let screens = NSScreen.screens.map { $0.frame.size }
        return windows.contains { w in
            guard (w[kCGWindowOwnerPID as String] as? pid_t) == front.processIdentifier,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
            return screens.contains { $0.width == b["Width"] && $0.height == b["Height"] }
        }
    }

    // MARK: Core Audio plumbing
    private static func objects(_ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ value: inout T) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr
    }
}
