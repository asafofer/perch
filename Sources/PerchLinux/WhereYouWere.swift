import CPerchLinux
import Foundation

/// The window you were in, taken before Perch has to bring another forward (a reply it pastes, a session it resumes in a
/// new terminal window), to put you back there once it is done. Perch's own panel never counts.
@MainActor
struct WhereYouWere {
    let window: Window?

    static func now() -> WhereYouWere {
        guard let w = X11.activeWindow(), X11.pid(of: w) != getpid() else { return WhereYouWere(window: nil) }
        return WhereYouWere(window: w)
    }

    /// That window back in front, on its desktop, if it is still open.
    func restore() {
        guard let window, X11.clientWindows().contains(window) else { return }
        X11.activate(window)
    }
}
