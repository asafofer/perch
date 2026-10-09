import AppKit
import Carbon.HIToolbox

/// Global shortcuts. Carbon hotkeys need no permission; the bare Cmd+Option tap needs Accessibility.
@MainActor
final class HotkeyService {
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: () -> Void] = [:]
    private var flagsMonitor: Any?
    private var chordStart: Date?
    private var chordDirty = false
    var onChordTap: (() -> Void)?
    private var localMonitor: Any?

    func register(keyCode: Int, modifiers: Int, id: UInt32, action: @escaping () -> Void) {
        installHandlerIfNeeded()
        handlers[id] = action
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x50524348), id: id)  // 'PRCH'
        if let old = refs.removeValue(forKey: id) { UnregisterEventHotKey(old) }
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if let ref { refs[id] = ref }
    }

    func unregister(id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        handlers[id] = nil
    }

    private static var handlerInstalled = false
    private func installHandlerIfNeeded() {
        guard !Self.handlerInstalled else { return }
        Self.handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let me = Unmanaged<HotkeyService>.fromOpaque(userData!).takeUnretainedValue()
            DispatchQueue.main.async { me.handlers[hk.id]?() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    /// Tap Command+Option together, with nothing else pressed, and release within 0.6s.
    /// Granting Accessibility after launch only takes effect for monitors created afterwards, so they are rebuilt.
    func restartChordMonitor() {
        if let m = flagsMonitor { NSEvent.removeMonitor(m); flagsMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        startChordMonitor()
    }

    func startChordMonitor() {
        let trusted = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary)
        if !trusted { NSLog("Perch: Accessibility not granted, Command+Option tap disabled (use Command+Option+Space)") }
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        // While Perch's own card is the key window, the keys arrive locally instead.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }
    }

    private func handle(_ event: NSEvent) {
        if event.type == .keyDown { chordDirty = true; return }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if flags == [.command, .option] {
            if chordStart == nil { chordStart = Date(); chordDirty = false }
        } else if flags.isEmpty {
            if let start = chordStart, !chordDirty, Date().timeIntervalSince(start) < 0.6 { onChordTap?() }
            chordStart = nil
        } else if flags != [.command] && flags != [.option] {
            chordDirty = true
        }
    }
}
