import AppKit
import PerchCore

/// The real icons of the apps the UI talks about, read from this Mac and handed to the web view as data URLs.
enum AppIcons {
    /// Found by bundle id: Codex installs as Codex.app or ChatGPT.app, in /Applications or ~/Applications.
    private static let apps: [String: (bundle: String, fallback: String)] = [
        "claude": ("com.anthropic.claudefordesktop", "/Applications/Claude.app"),
        "codex": ("com.openai.codex", "/Applications/Codex.app"),
        // The OpenCode desktop app, when it is installed. pi has no app: the page draws its own mark.
        "opencode": ("ai.opencode.desktop", "/Applications/OpenCode.app"),
        "xcode": ("com.apple.dt.Xcode", "/Applications/Xcode.app"),
        "numbers": ("com.apple.iWork.Numbers", "/Applications/Numbers.app"),
        "terminal": ("com.apple.Terminal", "/System/Applications/Utilities/Terminal.app"),
    ].merging(Terminals.keys.filter { $0.value != "terminal" }.map { ($0.value, ($0.key, "")) }, uniquingKeysWith: { a, _ in a })

    /// Where an app lives on this Mac, if it is installed.
    static func url(_ key: String) -> URL? {
        guard let app = apps[key] else { return nil }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundle) { return url }
        return !app.fallback.isEmpty && FileManager.default.fileExists(atPath: app.fallback) ? URL(fileURLWithPath: app.fallback) : nil
    }

    static func all() -> [String: String] {
        var out: [String: String] = [:]
        for key in apps.keys { if let path = url(key)?.path, let data = dataURL(forFile: path) { out[key] = data } }
        return out
    }

    private static func dataURL(forFile path: String, points: CGFloat = 64) -> String? {
        let icon = NSWorkspace.shared.icon(forFile: path)
        let size = NSSize(width: points, height: points)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(points), pixelsHigh: Int(points), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        icon.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return "data:image/png;base64," + png.base64EncodedString()
    }
}

/// Whether an agent is on this Mac: its app, its command, or the folder it keeps sessions in.
enum AgentPresence {
    static func installed(_ a: Agent) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path, fm = FileManager.default
        let folders: [String: [String]] = [
            "claude": [home + "/.claude"], "codex": [home + "/.codex"],
            "opencode": [home + "/.local/share/opencode/opencode.db"], "pi": [home + "/.pi/agent"],
        ]
        if (folders[a.id] ?? []).contains(where: fm.fileExists(atPath:)) { return true }
        if AppIcons.url(a.id) != nil { return true }
        return ["/opt/homebrew/bin/", "/usr/local/bin/", home + "/.local/bin/", home + "/.bun/bin/"].contains { fm.isExecutableFile(atPath: $0 + a.id) }
    }
}
