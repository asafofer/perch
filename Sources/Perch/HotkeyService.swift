import AppKit
import Carbon.HIToolbox
import PerchCore

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
    /// The modifiers whose tap opens Perch; empty when the shortcut is a key combo (or while one is being recorded).
    private var tapFlags: NSEvent.ModifierFlags = [.command, .option]
    private static let openId: UInt32 = 4
    /// False when another app already holds the combo, so pressing it would do nothing here.
    private(set) var openCombo = true

    /// Makes `s` the shortcut that opens Perch: a tap watches the modifiers, a combo is a Carbon hotkey. Both call `onChordTap`.
    func apply(_ s: Shortcut) {
        unregister(id: Self.openId)
        chordStart = nil; openCombo = true
        switch s.kind {
        case .tap: tapFlags = s.mods.eventFlags
        case .combo:
            tapFlags = []
            if let code = s.keyCode { openCombo = register(keyCode: code, modifiers: s.mods.carbonFlags, id: Self.openId) { [weak self] in self?.onChordTap?() } }
        }
    }
    /// While a new shortcut is being recorded, the old one must not fire.
    func pauseOpen() { unregister(id: Self.openId); tapFlags = []; chordStart = nil }

    @discardableResult
    func register(keyCode: Int, modifiers: Int, id: UInt32, action: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()
        handlers[id] = action
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x50524348), id: id)  // 'PRCH'
        if let old = refs.removeValue(forKey: id) { UnregisterEventHotKey(old) }
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if let ref { refs[id] = ref }
        return status == noErr
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
            // A shortcut's key never reaches the tap monitor (the hotkey takes it), so Command+Option+Y must not also
            // count as tapping Command+Option.
            MainActor.assumeIsolated { me.chordDirty = true }
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
        guard !tapFlags.isEmpty else { return }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if flags == tapFlags {
            if chordStart == nil { chordStart = Date(); chordDirty = false }
        } else if flags.isEmpty {
            if let start = chordStart, !chordDirty, Date().timeIntervalSince(start) < 0.6 { onChordTap?() }
            chordStart = nil
        } else if !flags.isSubset(of: tapFlags) {
            chordDirty = true
        }
    }
}

extension ShortcutMods {
    init(_ flags: NSEvent.ModifierFlags) {
        var m: ShortcutMods = []
        if flags.contains(.control) { m.insert(.control) }
        if flags.contains(.option) { m.insert(.option) }
        if flags.contains(.shift) { m.insert(.shift) }
        if flags.contains(.command) { m.insert(.command) }
        self = m
    }
    var eventFlags: NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if contains(.control) { f.insert(.control) }
        if contains(.option) { f.insert(.option) }
        if contains(.shift) { f.insert(.shift) }
        if contains(.command) { f.insert(.command) }
        return f
    }
    var carbonFlags: Int {
        (contains(.control) ? controlKey : 0) | (contains(.option) ? optionKey : 0) | (contains(.shift) ? shiftKey : 0) | (contains(.command) ? cmdKey : 0)
    }
}
