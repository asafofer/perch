import CPerchLinux
import Foundation
import PerchCore

// Perch for Linux. X11 only: the panel, the keys and the window reading all need it (GDK_BACKEND is forced, so it also
// runs under XWayland).
setvbuf(stdout, nil, _IOLBF, 0)   // logs reach a file or pipe as they happen
setenv("GDK_BACKEND", "x11", 1)
setenv("WEBKIT_DISABLE_COMPOSITING_MODE", "0", 0)
gtk_init()

/// Where ui/ is: $PERCH_UI, beside the binary (an install), or the repo's (a build run from the checkout).
func uiFolder() -> URL? {
    let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
    var candidates = [exe.appendingPathComponent("ui"), exe.appendingPathComponent("../share/perch/ui"),
                      URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("ui")]
    if let env = ProcessInfo.processInfo.environment["PERCH_UI"] { candidates.insert(URL(fileURLWithPath: env), at: 0) }
    // .build/<triple>/debug/perch -> the checkout's ui/
    candidates.append(exe.appendingPathComponent("../../../ui"))
    return candidates.map(\.standardizedFileURL).first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("index.html").path) }
}

MainActor.assumeIsolated {
    guard let ui = uiFolder() else { print("perch: ui/index.html not found (set PERCH_UI)"); exit(1) }
    let panel = Panel()
    let screen = ScreenChooser.home()
    panel.setFrame(NotchGeometry.panelFrame(for: screen.screenInfo))
    panel.onMessage = { m in if ProcessInfo.processInfo.environment["PERCH_TRACE"] != nil { print("page:", m) } }
    panel.onLoaded = {
        let projects = FakeSessionProvider().parkedProjects()
        var machine = NotchMachine(projectCount: projects.count)
        machine.send(.openSwitcher)
        var snap = UISnapshot(machine: machine, projects: projects, screen: screen.screenInfo, timerToken: 0)
        snap.shown = ListFilter.ordered(projects, "", now: Date())
        if let data = try? JSONEncoder().encode(snap), let json = String(data: data, encoding: .utf8) {
            panel.evaluate("window.perch && window.perch.apply(\(json))")
        }
        panel.ignoresMouseEvents = false
    }
    panel.load(ui.appendingPathComponent("index.html"))
    panel.show()
}
GLoop.run()
