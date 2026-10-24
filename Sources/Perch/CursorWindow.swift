import AppKit
import PerchCore

/// Going back to a Cursor chat. Cursor has no link that opens a chat that already exists, so Pick up opens the chat's folder:
/// Cursor brings the window that has the folder open forward (and opens one if there is none).
enum CursorWindow {
    static var appURL: URL? { AppIcons.url("cursor") }

    /// `folder` nil, or the made-up one a chat without a folder is kept under: just bring Cursor forward.
    static func open(folder: String?) {
        guard let app = appURL else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        guard let folder, !folder.hasSuffix("/.cursor/projects/\(CursorApp.noFolder)") else {
            NSWorkspace.shared.openApplication(at: app, configuration: config)
            return
        }
        NSWorkspace.shared.open([URL(fileURLWithPath: folder, isDirectory: true)], withApplicationAt: app, configuration: config)
    }
}
