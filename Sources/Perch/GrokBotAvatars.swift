import AppKit

/// A Grok Bot bot's avatar, as Grok Bot draws it small: its shape's silhouette (the image Grok Bot ships for its menu bar
/// icon, `dist/electron-main/menubar-tray/assets/bot-<shape>@2x.png` inside the app's `app.asar`), filled with the bot's
/// colour. Read from the installed app, never shipped with Perch. Black is drawn white, as Grok Bot does on a dark page.
enum GrokBotAvatars {
    static let colors: [String: NSColor] = [
        "black": NSColor(white: 0.96, alpha: 1), "brown": hex(0x936439), "red": hex(0xFF263C), "orange": hex(0xFF6700), "yellow": hex(0xFF9800),
        "green": hex(0x00C972), "cyan": hex(0x00BCA6), "blue": hex(0x1084FE), "violet": hex(0x9159FE), "magenta": hex(0xFF309B), "gray": hex(0x777777),
    ]
    static func hex(_ v: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var drawn: [String: String] = [:]

    /// "tablet:yellow" as a PNG data URL, or nil when Grok Bot is not installed or has no image for that shape.
    static func dataURL<S: StringProtocol>(_ look: S) -> String? {
        let key = String(look)
        lock.lock(); let hit = drawn[key]; lock.unlock()
        if let hit { return hit }
        let parts = key.split(separator: ":").map(String.init)
        guard parts.count == 2, let color = colors[parts[1]], let app = AppIcons.url("grokbot"),
              let png = Asar.file("dist/electron-main/menubar-tray/assets/bot-\(parts[0])@2x.png", in: app.appendingPathComponent("Contents/Resources/app.asar")),
              let silhouette = NSImage(data: png), let url = tinted(silhouette, color) else { return nil }
        lock.lock(); drawn[key] = url; lock.unlock()
        return url
    }

    /// The silhouette's own alpha, filled with the colour: the eyes are holes in it, so they show the card behind.
    static func tinted(_ image: NSImage, _ color: NSColor, px: Int = 64) -> String? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: px, height: px)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        let r = NSRect(x: 0, y: 0, width: px, height: px)
        image.draw(in: r, from: .zero, operation: .copy, fraction: 1)
        color.setFill(); r.fill(using: .sourceIn)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:]).map { "data:image/png;base64," + $0.base64EncodedString() }
    }
}

/// Reads one file out of an Electron `.asar` archive: an 8-byte prefix, then a header (a pickled JSON index of every file,
/// each with its `size` and `offset` from the end of the header), then the files' bytes.
enum Asar {
    static func file(_ path: String, in archive: URL) -> Data? {
        guard let h = try? FileHandle(forReadingFrom: archive) else { return nil }
        defer { try? h.close() }
        func u32(_ d: Data, _ at: Int) -> Int { Int(d[d.startIndex + at]) | Int(d[d.startIndex + at + 1]) << 8 | Int(d[d.startIndex + at + 2]) << 16 | Int(d[d.startIndex + at + 3]) << 24 }
        guard let prefix = try? h.read(upToCount: 16), prefix.count == 16 else { return nil }
        let headerSize = u32(prefix, 4), jsonSize = u32(prefix, 12)
        guard headerSize > 0, jsonSize > 0, jsonSize < 64 << 20, (try? h.seek(toOffset: 16)) != nil,
              let json = try? h.read(upToCount: jsonSize), let index = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else { return nil }
        var node: [String: Any]? = index
        for part in path.split(separator: "/") { node = (node?["files"] as? [String: Any])?[String(part)] as? [String: Any] }
        guard let entry = node, entry["unpacked"] as? Bool != true, let size = entry["size"] as? Int,
              let offset = (entry["offset"] as? String).flatMap(UInt64.init) ?? (entry["offset"] as? Int).map(UInt64.init) else { return nil }
        guard (try? h.seek(toOffset: 8 + UInt64(headerSize) + offset)) != nil else { return nil }
        return try? h.read(upToCount: size)
    }
}
