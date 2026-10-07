import AppKit
import SwiftUI
import PerchCore
import PerchUI

@MainActor
final class NotchController {
    private let panel = NotchPanel()
    private let model: NotchViewModel
    private var screen: NSScreen
    private var timer: Task<Void, Never>?
    private var keyMonitor: Any?
    private var mouseMonitors: [Any] = []

    init(provider: SessionProviding) {
        screen = ScreenChooser.current()
        model = NotchViewModel(projects: provider.parkedProjects(), screen: screen.screenInfo)
        let host = NSHostingView(rootView: NotchRootView(model: model))
        host.sizingOptions = []
        host.layer?.backgroundColor = .clear
        panel.contentView = host
        place(on: screen)
        panel.orderFrontRegardless()
        model.onPhaseChange = { [weak self] old, new in self?.phaseChanged(old, new) }
        installMouseMonitors()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { guard let self, self.model.phase == .idle else { return }; self.place(on: ScreenChooser.current()) }
        }
    }

    func comeBack() { if model.phase == .idle { place(on: ScreenChooser.current()) }; model.send(.comeBack) }
    func confirm() { model.send(.confirm) }
    func toggleSwitcher() { if model.phase == .idle { place(on: ScreenChooser.current()) }; model.send(.openSwitcher) }

    private func place(on s: NSScreen) {
        screen = s
        model.screen = s.screenInfo
        panel.setFrame(NotchGeometry.panelFrame(for: s.screenInfo), display: true)
    }

    private func phaseChanged(_ old: NotchPhase, _ new: NotchPhase) {
        switch new {
        case .idle:
            timer?.cancel(); stopKeys(); panel.allowsKey = false; panel.ignoresMouseEvents = true
            model.barProgress = 1
        case .open:
            if old == .idle { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
            startKeys(); panel.allowsKey = true; panel.ignoresMouseEvents = false; panel.makeKey()
            restartTimer()
        case .switcher:
            if old == .idle { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
            timer?.cancel(); model.barProgress = 1
            startKeys(); panel.allowsKey = true; panel.ignoresMouseEvents = false; panel.makeKey()
        case .restoring:
            timer?.cancel()
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            timer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(3.3))
                if !Task.isCancelled { self?.model.send(.restoreFinished) }
            }
        }
    }

    private func restartTimer() {
        timer?.cancel()
        model.barProgress = 1
        guard model.machine.autoCollapses else { return }
        withAnimation(.linear(duration: 9)) { model.barProgress = 0 }
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(9))
            if !Task.isCancelled { self?.model.send(.timeout) }
        }
    }

    // MARK: keys
    private func startKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, self.model.phase != .idle else { return e }
            switch e.keyCode {
            case 36, 76: self.model.send(.confirm)                                  // Return, Enter
            case 53: self.model.send(.dismiss)                                      // Esc
            case 48: self.model.send(e.modifierFlags.contains(.shift) ? .previous : .next) // Tab
            case 125: self.model.send(.next)                                        // Down
            case 126: self.model.send(.previous)                                    // Up
            default: return e
            }
            if self.model.phase == .open { self.restartTimer() }
            return nil
        }
    }
    private func stopKeys() { if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil } }

    // MARK: mouse. Hover pauses the timer, and the panel only catches clicks over the visible card.
    private func installMouseMonitors() {
        let handler: (NSEvent?) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.mouseMoved() } }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: handler) { mouseMonitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { e in handler(e); return e }) { mouseMonitors.append(l) }
    }
    private func mouseMoved() {
        guard model.phase != .idle else { return }
        let inside = NotchGeometry.contentRect(for: model.phase, screen: model.screen).contains(NSEvent.mouseLocation)
        panel.ignoresMouseEvents = !inside
        if inside != model.machine.hovering {
            let wasCollapsing = model.machine.autoCollapses
            model.send(.hoverChanged(inside))
            if model.phase == .open {
                if inside && wasCollapsing { timer?.cancel(); withAnimation(.easeOut(duration: 0.2)) { model.barProgress = 1 } }
                else if !inside { restartTimer() }
            }
        }
    }
}
