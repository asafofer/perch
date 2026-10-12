import CPerchLinux
import Foundation

// OWNER: the input-and-desktop agent. STUB.
/// The menu-bar item's Linux twin: a StatusNotifierItem (D-Bus, through GIO) with Perch's menu.
@MainActor
final class Tray {
    struct Item { let title: String; let action: () -> Void }
    init(items: [Item?]) {}   // nil is a separator
    /// The page's drawing of your character, as PNG data, for the icon.
    func setIcon(png: Data) {}
}

/// Launch at login: ~/.config/autostart/perch.desktop.
enum Autostart {
    static var isOn: Bool { false }
    static func set(_ on: Bool) {}
}
