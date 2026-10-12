import CPerchLinux
import Foundation

// OWNER: the processes-and-terminals agent. STUB.
/// The clipboard, for the paste fallback of a reply: set text, and put back what was there.
@MainActor
enum Clipboard {
    typealias Saved = String?
    static func save() -> Saved { nil }
    static func restore(_ saved: Saved) {}
    static func set(_ text: String) {}
}
