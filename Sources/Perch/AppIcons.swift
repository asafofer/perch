import AppKit

/// The real icons of the apps the UI talks about, read from this Mac and handed to the web view as data URLs.
enum AppIcons {
    private static let paths: [String: String] = [
        "claude": "/Applications/Claude.app",
        "codex": "/Applications/Codex.app",
        "xcode": "/Applications/Xcode.app",
        "numbers": "/Applications/Numbers.app",
        "terminal": "/System/Applications/Utilities/Terminal.app",
    ]

    static func all() -> [String: String] {
        var out: [String: String] = [:]
        for (key, path) in paths where FileManager.default.fileExists(atPath: path) {
            if let url = dataURL(forFile: path) { out[key] = url }
        }
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
