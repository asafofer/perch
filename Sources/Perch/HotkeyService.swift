import AppKit
import Carbon.HIToolbox
import PerchCore

/// Global shortcuts. Carbon hotkeys need no permission; the bare Cmd+Option tap needs Accessibility.
@MainActor
final class HotkeyService {
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: () -> Void] = [:]
    private var flagsMonitor: Any?
    var onChordTap: (() -> Void)?
    private var localMonitor: Any?
    /// The tap that opens Perch; its modifiers are empty when the shortcut is a key combo (or while one is being recorded).
    private var tap = ModifierTap([.command, .option])
    private static let openId: UInt32 = 4
    /// False when another app already holds the combo, so pressing it would do nothing here.
    private(set) var openCombo = true

    /// Makes `s` the shortcut that opens Perch: a tap watches the modifiers, a combo is a Carbon hotkey. Both call `onChordTap`.
    func apply(_ s: Shortcut) {
        unregister(id: Self.openId)
        tap.reset(); openCombo = true
        switch s.kind {
        case .tap: tap.mods = s.mods
        case .combo:
            tap.mods = []
            if let code = s.keyCode { openCombo = register(keyCode: code, modifiers: s.mods.carbonFlags, id: Self.openId) { [weak self] in self?.onChordTap?() } }
        }
    }
    /// While a new shortcut is being recorded, none of Perch's own shortcuts may fire: a Carbon hotkey takes its key before the
    /// recorder sees it (pressing Control+Option+Q would quit instead of being refused).
    func pauseAll() {
        unregister(id: Self.openId); tap.mods = []; tap.reset()
        for ref in refs.values { UnregisterEventHotKey(ref) }
        refs = [:]
    }
    /// After recording: the others come back (the open shortcut is applied again by `apply`).
    func resumeAll() {
        for id in specs.keys where refs[id] == nil { arm(id) }
    }
    private var specs: [UInt32: (key: Int, mods: Int)] = [:]
    @discardableResult
    private func arm(_ id: UInt32) -> Bool {
        guard let spec = specs[id] else { return false }
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x50524348), id: id)  // 'PRCH'
        if let old = refs.removeValue(forKey: id) { UnregisterEventHotKey(old) }
        let status = RegisterEventHotKey(UInt32(spec.key), UInt32(spec.mods), hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if let ref { refs[id] = ref }
        return status == noErr
    }

    @discardableResult
    func register(keyCode: Int, modifiers: Int, id: UInt32, action: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()
        handlers[id] = action
        specs[id] = (keyCode, modifiers)
        return arm(id)
    }

    func unregister(id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        handlers[id] = nil; specs[id] = nil
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
            MainActor.assumeIsolated { me.tap.keyDown() }
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
        if event.type == .keyDown { tap.keyDown(); return }
        // Every key press on the system, ones another app's hotkey takes before they reach this monitor included.
        let keyDowns = Int(CGEventSource.counterForEventType(.hidSystemState, eventType: .keyDown))
        if tap.flagsChanged(ShortcutMods(event.modifierFlags), keyDowns: keyDowns) { onChordTap?() }
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
