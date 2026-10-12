import CPerchLinux
import Foundation

// OWNER: the input-and-desktop agent. STUB.
/// When Perch must not speak up on its own: a call (microphone or camera in use), a presentation (a full-screen window).
enum Quiet {
    /// Why it should stay quiet now, in a few words, or nil.
    @MainActor static func reason() -> String? { nil }
    /// A launcher (Rofi, Ulauncher, Albert, xfce4-appfinder, Whisker menu ...) has the keyboard: its name, else nil.
    @MainActor static func launcherOpen() -> String? { nil }
}
