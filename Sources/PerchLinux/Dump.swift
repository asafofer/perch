import CPerchLinux
import Foundation
import PerchCore

/// `--dump`: what Perch sees on this machine, printed. The displays, where Show Perch on points, every session with what
/// its card would say and where Pick up would take it, the agents running now, herdr's clients, the icons found and
/// whether Perch would speak up on its own. PERCH_HOME reads a stand-in home's sessions instead of yours.
/// With `--watch` it then stays, and prints a line each time the session folders change (Ctrl+C ends it).
@MainActor
enum Dump {
    static func run(watch: Bool = CommandLine.arguments.contains("--watch")) {
        for s in Screen.screens { print("screen: \(s.localizedName) | \(s.displayID) | \(Int(s.frame.width))x\(Int(s.frame.height)) | notch: no") }
        print("show on: \(Prefs.showOn.raw) -> \(ScreenChooser.target().localizedName)")
        print("agents here: \(Agent.all.filter(AgentPresence.installed).map(\.id).joined(separator: ", "))")
        let provider = RealSessionProvider()
        let projects = provider.parkedProjects()
        for p in projects {
            let opens = "\(p.via ?? Terminals.preferred)\(p.host.map { " (\($0))" } ?? ""): \(p.pid.map { "running, pid \($0)" } ?? Agent.of(p.app).resume(p.sessionId ?? "?"))"
            print("\(p.name) | \(p.app) | \(p.branch ?? "-") | left \(p.at) (\(p.away) ago) | \(p.status.kind): \(p.status.text)")
            print("   title:    \(p.topic)\n   headline: \(p.headline)\n   context:  \(p.context)\n   next:     \(p.next)\n   opens:    \(opens)")
        }
        if projects.isEmpty { print("no sessions in the last 14 days") }
        print("per agent: " + provider.counts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value.count)" }.joined(separator: ", "))
        let (hits, viewers) = LiveSessions.scan()
        for hit in hits {
            let place: String
            switch hit.place {
            case .herdr(let pane, _, let session): place = "herdr \(session) pane \(pane)" + (hit.viewer.map { ", shown on \($0.tty)" } ?? ", no herdr client attached")
            case .cmux(let w, let s): place = "cmux workspace \(w.prefix(8)) surface \(s.prefix(8))"
            case .tab: place = "a tab"
            }
            print("running: \(hit.agent) pid \(hit.pid) in \(hit.cwd) on \(hit.tty), \(place), in \(hit.app ?? "no app")")
        }
        for v in viewers { print("herdr client: session \(v.session) on \(v.tty) in \(v.app ?? "no app")") }
        let icons = AppIcons.all()
        print("icons: " + icons.keys.sorted().map { "\($0) (\(icons[$0]!.hasPrefix("data:image/svg") ? "svg" : "png"), \(icons[$0]!.count / 1024) KB)" }.joined(separator: ", "))
        print("terminal: \(Terminals.preferred)")
        print("speak up on its own now: \(Quiet.reason().map { "no, \($0)" } ?? "yes")")
        guard watch else { return }
        let w = Watcher()
        w.onChange = { print("changed: \(Date())") }
        w.start()
        print("watching \(w.count) folders")
        GLoop.run()
    }
}
