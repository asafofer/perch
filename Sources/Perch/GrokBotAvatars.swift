import AppKit
import CoreImage

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
    /// Drawn once per look; nil remembered too (no Grok Bot, or no image for that shape), so it is not looked for again.
    nonisolated(unsafe) private static var drawn: [String: String?] = [:]

    /// "tablet:yellow" as a PNG data URL, or nil when Grok Bot is not installed or has no image for that shape.
    static func dataURL<S: StringProtocol>(_ look: S) -> String? {
        let key = String(look)
        lock.lock(); let hit = drawn[key]; lock.unlock()
        if let hit { return hit }
        let url = draw(key)
        lock.lock(); drawn[key] = .some(url); lock.unlock()
        return url
    }

    private static func draw(_ key: String) -> String? {
        let parts = key.split(separator: ":").map(String.init)
        guard parts.count == 2, let color = colors[parts[1]], let app = AppIcons.url("grokbot"),
              let png = Asar.file("dist/electron-main/menubar-tray/assets/bot-\(parts[0])@2x.png", in: app.appendingPathComponent("Contents/Resources/app.asar")),
              let url = tinted(png, color) else { return nil }
        return url
    }

    /// The silhouette's own alpha, filled with the colour: the eyes are holes in it, so they show the card behind. Grok Bot's
    /// image is 32 px, too coarse for the card, so it is enlarged smoothly, softened a little, and its edge steepened again:
    /// a clean outline at any size, still anti-aliased.
    static func tinted(_ png: Data, _ color: NSColor, px: CGFloat = 96, soften: CGFloat = 0.8, steep: CGFloat = 5) -> String? {
        guard let src = CIImage(data: png), src.extent.width > 0, let rgb = color.usingColorSpace(.sRGB) else { return nil }
        let scale = px / src.extent.width, frame = CGRect(x: 0, y: 0, width: px, height: px)
        let alpha = src.applyingFilter("CILanczosScaleTransform", parameters: ["inputScale": scale, "inputAspectRatio": 1])
            .clampedToExtent().applyingFilter("CIGaussianBlur", parameters: ["inputRadius": soften * scale]).cropped(to: frame)
            .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: steep), "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: (1 - steep) / 2)])
            .applyingFilter("CIColorClamp")
        let fill = CIImage(color: CIColor(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent))
        let out = fill.applyingFilter("CISourceInCompositing", parameters: ["inputBackgroundImage": alpha]).cropped(to: frame)
        guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
              let data = CIContext().pngRepresentation(of: out, format: .RGBA8, colorSpace: sRGB) else { return nil }
        return "data:image/png;base64," + data.base64EncodedString()
    }
}

/// Reads one file out of an Electron `.asar` archive: an 8-byte prefix, then a header (a pickled JSON index of every file,
/// each with its `size` and `offset` from the end of the header), then the files' bytes.
enum Asar {
    private static let lock = NSLock()
    /// The index of the archive read last, kept while the file is the same (path and modification date).
    nonisolated(unsafe) private static var cached: (key: String, headerSize: Int, index: [String: Any])?

    static func file(_ path: String, in archive: URL) -> Data? {
        guard let h = try? FileHandle(forReadingFrom: archive) else { return nil }
        defer { try? h.close() }
        let key = archive.path + "|" + String(describing: (try? archive.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate)
        lock.lock(); var hit = cached?.key == key ? cached : nil; lock.unlock()
        if hit == nil {
            func u32(_ d: Data, _ at: Int) -> Int { Int(d[d.startIndex + at]) | Int(d[d.startIndex + at + 1]) << 8 | Int(d[d.startIndex + at + 2]) << 16 | Int(d[d.startIndex + at + 3]) << 24 }
            guard let prefix = try? h.read(upToCount: 16), prefix.count == 16 else { return nil }
            let headerSize = u32(prefix, 4), jsonSize = u32(prefix, 12)
            guard headerSize > 0, jsonSize > 0, jsonSize < 64 << 20, (try? h.seek(toOffset: 16)) != nil,
                  let json = try? h.read(upToCount: jsonSize), let index = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else { return nil }
            hit = (key, headerSize, index)
            lock.lock(); cached = hit; lock.unlock()
        }
        guard let (_, headerSize, index) = hit else { return nil }
        var node: [String: Any]? = index
        for part in path.split(separator: "/") { node = (node?["files"] as? [String: Any])?[String(part)] as? [String: Any] }
        guard let entry = node, entry["unpacked"] as? Bool != true, let size = entry["size"] as? Int,
              let offset = (entry["offset"] as? String).flatMap(UInt64.init) ?? (entry["offset"] as? Int).map(UInt64.init) else { return nil }
        guard (try? h.seek(toOffset: 8 + UInt64(headerSize) + offset)) != nil else { return nil }
        return try? h.read(upToCount: size)
    }
}
