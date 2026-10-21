import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers
import PerchCore

/// The real icons of the apps the UI talks about, read from this Mac and handed to the web view as data URLs.
enum AppIcons {
    /// Found by bundle id: Codex installs as Codex.app or ChatGPT.app, in /Applications or ~/Applications.
    private static let apps: [String: (bundle: String, fallback: String)] = [
        "claude": ("com.anthropic.claudefordesktop", "/Applications/Claude.app"),
        // Cowork and chats are the Claude app's own.
        "cowork": ("com.anthropic.claudefordesktop", "/Applications/Claude.app"),
        "chat": ("com.anthropic.claudefordesktop", "/Applications/Claude.app"),
        "codex": ("com.openai.codex", "/Applications/Codex.app"),
        // The OpenCode desktop app, when it is installed. pi has no app: the page draws its own mark.
        "opencode": ("ai.opencode.desktop", "/Applications/OpenCode.app"),
        "conductor": (ConductorApp.bundle, "/Applications/Conductor.app"),
        "xcode": ("com.apple.dt.Xcode", "/Applications/Xcode.app"),
        "numbers": ("com.apple.iWork.Numbers", "/Applications/Numbers.app"),
        "terminal": ("com.apple.Terminal", "/System/Applications/Utilities/Terminal.app"),
    ].merging(Terminals.keys.filter { $0.value != "terminal" }.map { ($0.value, ($0.key, "")) }, uniquingKeysWith: { a, _ in a })

    /// The agent's own mark, shipped inside its app, where the app's icon is no longer the agent's: Codex's app now wears
    /// ChatGPT's icon but still carries the Codex mark in its resources.
    private static let marks: [String: String] = ["codex": "icon-codex-light.png"]

    /// Whether the page could get a real icon for this key at all (pi has no app).
    static func knows(_ key: String) -> Bool { apps[key] != nil }

    /// Where an app lives on this Mac, if it is installed.
    static func url(_ key: String) -> URL? {
        guard let app = apps[key] else { return nil }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundle) { return url }
        return !app.fallback.isEmpty && FileManager.default.fileExists(atPath: app.fallback) ? URL(fileURLWithPath: app.fallback) : nil
    }

    static func all() -> [String: String] {
        var out: [String: String] = [:]
        for key in apps.keys { if let app = url(key), let data = dataURL(for: image(key, app)) { out[key] = data } }
        return out
    }

    /// A file attached to a reply or a new session, as Finder shows it: its own icon, or for a picture a small
    /// thumbnail of it (one too big to read quickly keeps its icon).
    static func file(_ path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey])
        if values?.contentType?.conforms(to: .image) == true, (values?.fileSize ?? .max) < 40_000_000, let picture = NSImage(contentsOf: url) {
            return dataURL(for: picture, points: 32, fill: true)
        }
        // anything else Quick Look can show (a film's frame, a text file's first lines, a PDF's first page) as Finder draws it
        if let thumb = quickLook(url) { return dataURL(for: thumb, points: 32, fill: true) }
        return dataURL(for: NSWorkspace.shared.icon(forFile: path), points: 32)
    }

    private final class Box: @unchecked Sendable { var image: NSImage? }
    /// Quick Look's thumbnail of a file, waited for here (this runs off the main thread); nothing when it has none in time.
    private static func quickLook(_ url: URL) -> NSImage? {
        let req = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 32, height: 32), scale: 2, representationTypes: .thumbnail)
        let box = Box(), done = DispatchSemaphore(value: 0)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { rep, _ in box.image = rep?.nsImage; done.signal() }
        _ = done.wait(timeout: .now() + 1.5)
        return box.image
    }

    /// The design page's stand-ins for attachments, by kind (file.png, file.pdf, ...): this Mac's own icons, and for a
    /// picture a thumbnail of one of the page's wallpapers.
    static func designFiles(wallpaper: URL) -> [String: String] {
        var out: [String: String] = [:]
        for ext in ["pdf", "txt", "md", "swift", "js", "json", "zip", "mov", "csv"] {
            if let type = UTType(filenameExtension: ext), let data = dataURL(for: NSWorkspace.shared.icon(for: type), points: 32) { out["file." + ext] = data }
        }
        if let data = dataURL(for: NSWorkspace.shared.icon(for: .folder), points: 32) { out["file.folder"] = data }
        if let picture = NSImage(contentsOf: wallpaper), let data = dataURL(for: picture, points: 32, fill: true) { out["file.png"] = data; out["file.jpg"] = data }
        return out
    }

    private static func image(_ key: String, _ app: URL) -> NSImage {
        if let mark = marks[key], let image = NSImage(contentsOf: app.appendingPathComponent("Contents/Resources/" + mark)) { return image }
        return NSWorkspace.shared.icon(forFile: app.path)
    }

    /// fill: cut to a square from the middle, as a thumbnail is, rather than drawn whole.
    private static func dataURL(for icon: NSImage, points: CGFloat = 64, fill: Bool = false) -> String? {
        let size = NSSize(width: points, height: points)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(points), pixelsHigh: Int(points), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        var from = NSRect.zero
        if fill, icon.size.width > 0, icon.size.height > 0 {
            let side = min(icon.size.width, icon.size.height)
            from = NSRect(x: (icon.size.width - side) / 2, y: (icon.size.height - side) / 2, width: side, height: side)
        }
        icon.draw(in: NSRect(origin: .zero, size: size), from: from, operation: .copy, fraction: 1)
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
            "cowork": [home + "/Library/Application Support/Claude/local-agent-mode-sessions"],
            "chat": [home + "/Library/Application Support/Claude/IndexedDB/https_claude.ai_0.indexeddb.blob"],
        ]
        // Only the folder says Cowork or chats were used: the Claude app alone is not enough (it may be Code only).
        if ["cowork", "chat"].contains(a.id) { return (folders[a.id] ?? []).contains(where: fm.fileExists(atPath:)) }
        if (folders[a.id] ?? []).contains(where: fm.fileExists(atPath:)) { return true }
        if AppIcons.url(a.id) != nil { return true }
        return ["/opt/homebrew/bin/", "/usr/local/bin/", home + "/.local/bin/", home + "/.bun/bin/"].contains { fm.isExecutableFile(atPath: $0 + a.id) }
    }
}
