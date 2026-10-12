import CPerchLinux
import Foundation
import PerchCore

// Perch for Linux: the Mac's AppDelegate (Sources/Perch/main.swift). X11 only: the panel, the keys and reading windows all
// need it, so GDK_BACKEND is forced (it also runs under XWayland, with less: Wayland hides other apps' windows).
setvbuf(stdout, nil, _IOLBF, 0)   // logs reach a file or pipe as they happen
setenv("GDK_BACKEND", "x11", 1)
let args = CommandLine.arguments

if let flag = args.first(where: { $0 == "--install-hooks" || $0 == "--uninstall-hooks" }) {
    for agent in HookInstaller.agents {
        do { if flag == "--install-hooks" { try HookInstaller.install(agent) } else { try HookInstaller.uninstall(agent) }; print("\(agent): \(HookInstaller.isInstalled(agent) ? "on" : "off")") }
        catch { print("\(agent): \(error.localizedDescription)") }
    }
    exit(0)
}

// Perch's own X connection (XServer) is used from background threads beside GDK's.
XInitThreads()
gtk_init()
if args.contains("--dump") { MainActor.assumeIsolated { Dump.run() }; exit(0) }
if MainActor.assumeIsolated({ TerminalsDebug.handle(args) }) { exit(0) }
if MainActor.assumeIsolated({ desktopCheck(args) }) { GLoop.run(); exit(0) }

/// Where ui/ is: $PERCH_UI, beside the binary (an install), or the checkout's (a build run from the repo).
func uiFolder() -> URL? {
    let exe = URL(fileURLWithPath: "/proc/self/exe").resolvingSymlinksInPath().deletingLastPathComponent()
    var candidates = [exe.appendingPathComponent("ui"), exe.appendingPathComponent("../share/perch/ui"),
                      exe.appendingPathComponent("../../../ui"),   // .build/<triple>/<config>/PerchLinux
                      URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("ui")]
    if let env = ProcessInfo.processInfo.environment["PERCH_UI"] { candidates.insert(URL(fileURLWithPath: env), at: 0) }
    return candidates.map(\.standardizedFileURL).first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("index.html").path) }
}

/// One Perch at a time: a second one would take over the hook socket.
func takeLock() -> Bool {
    try? FileManager.default.createDirectory(at: HookInstaller.dir, withIntermediateDirectories: true)
    let fd = open(HookInstaller.dir.appendingPathComponent("perch.lock").path, O_CREAT | O_RDWR, 0o600)
    return fd >= 0 && flock(fd, LOCK_EX | LOCK_NB) == 0   // held until Perch exits
}

@MainActor
final class App {
    var controller: NotchController?
    var activity: ActivityMonitor?
    var tray: Tray?
    let hotkeys = HotkeyService()

    func start() {
        guard let ui = uiFolder() else { print("perch: ui/index.html not found (set PERCH_UI)"); exit(1) }
        HookInstaller.upgrade()
        if Autostart.isOn { Autostart.set(true) }   // launch at login follows the binary if it moved
        let sample = args.contains("--fake") || args.contains("--demo")
        let provider: SessionProviding = sample ? FakeSessionProvider() : RealSessionProvider()
        let c = NotchController(provider: provider, ui: ui)
        controller = c
        c.onQuit = { GLoop.quit() }

        // While the panel says an answer or a request arrived, its buttons answer to Super+Alt and a key. Only then.
        // Codes are the Mac's (kVK): Return, R, period, Y, N, 1, 2, 3.
        let activityCodes: [String: Int] = ["pick": 36, "open": 36, "reply": 15, "gone": 47, "allow": 16, "deny": 45, "pick1": 18, "pick2": 19, "pick3": 20]
        let activityIds = Dictionary(uniqueKeysWithValues: activityCodes.keys.sorted().enumerated().map { ($1, UInt32(20 + $0)) })
        c.onActivityKeys = { [hotkeys] keys in
            for (name, id) in activityIds where !keys.contains(name) { hotkeys.unregister(id: id) }
            // All of them Super+Alt and a key: the Mac's Command+R for Reply would be Super+R, XFCE's run dialog.
            for name in keys { if let code = activityCodes[name], let id = activityIds[name] { hotkeys.register(keyCode: code, modifiers: [.command, .option], id: id) { c.activityKey(name) } } }
        }
        // What is new has one key, Super+Alt+Return, registered only while the card shows.
        c.onWhatsNewKey = { [hotkeys] on in
            if on { hotkeys.register(keyCode: 36, modifiers: [.command, .option], id: 40) { c.whatsNewDone() } } else { hotkeys.unregister(id: 40) }
        }
        hotkeys.onChordTap = { c.chordTap() }
        hotkeys.onButton = { down in c.mouseButton(down: down) }
        c.hearsButtons = hotkeys.hearsButtons
        hotkeys.apply(Prefs.openShortcut)
        c.openComboWorks = { [hotkeys] in hotkeys.openCombo }
        c.onShortcutRecording = { [hotkeys] recording in if recording { hotkeys.pauseAll() } else { hotkeys.resumeAll(); hotkeys.apply(Prefs.openShortcut) } }
        hotkeys.startChordMonitor()

        if !sample {
            var seconds: TimeInterval = 20 * 60
            if let i = args.firstIndex(of: "--idle"), args.indices.contains(i + 1), let v = TimeInterval(args[i + 1]) { seconds = v }
            let monitor = ActivityMonitor(threshold: seconds)
            if !args.contains("--idle") { monitor.threshold = TimeInterval(Prefs.idleMinutes * 60) }
            c.onIdleMinutesChanged = { [weak monitor] m in monitor?.threshold = TimeInterval(m * 60) }
            monitor.onReturn = { since in c.comeBack(proactive: true, awaySince: since) }
            activity = monitor
            installTray(c)
            if let step = Prefs.resumeStep { Prefs.resumeStep = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { c.startOnboarding(step: step) } }
            else if !Prefs.onboarded { DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { c.startOnboarding() } }
        }

        if args.contains("--simulate") { c.holdOpen = true; DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { c.comeBack() } }
        if args.contains("--hello") { DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { c.sayHello() } }
        if args.contains("--onboarding") { DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { c.startOnboarding() } }
        if args.contains("--activity") { DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { c.playActivityDemo() } }
        if args.contains("--show") { DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { c.comeBack() } }
        if args.contains("--list") { DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { c.toggleSwitcher() } }
        if args.contains("--demo") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { c.comeBack() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { c.confirm() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 12.0) { GLoop.quit() }
        }
    }

    private func installTray(_ c: NotchController) {
        let t = Tray(items: [
            Tray.Item(title: "Where was I") { c.comeBack() },
            Tray.Item(title: "All sessions") { c.toggleSwitcher() },
            nil,
            Tray.Item(title: "Customize your character\u{2026}") { c.startOnboarding(step: 1, characterOnly: true) },
            Tray.Item(title: "Choose apps\u{2026}") { c.startOnboarding(step: c.appsStep) },
            Tray.Item(title: "Set up Perch\u{2026}") { c.startOnboarding() },
            nil,
            Tray.Item(title: "Quit Perch") { GLoop.quit() },
        ])
        c.onMenuIcon = { [weak t] png in t?.setIcon(png: png) }
        tray = t
    }
}

guard takeLock() else { print("perch: already running"); exit(0) }
let app = MainActor.assumeIsolated { () -> App in let a = App(); a.start(); return a }
GLoop.run()
withExtendedLifetime(app) {}
