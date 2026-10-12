import CPerchLinux
import Foundation

// OWNER: the processes-and-terminals agent. STUB.
/// The window you were in, taken before Perch brings another forward, to put you back there after.
@MainActor
struct WhereYouWere {
    let window: Window?
    static func now() -> WhereYouWere { WhereYouWere(window: X11.activeWindow()) }
    func restore() { if let window { X11.activate(window) } }
}
