import AppKit

/// Reply borrows the clipboard to paste. This puts back what you had, every type of it.
enum Clipboard {
    typealias Saved = [[NSPasteboard.PasteboardType: Data]]
    static func save() -> Saved {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in
            Dictionary(item.types.compactMap { t in item.data(forType: t).map { (t, $0) } }, uniquingKeysWith: { a, _ in a })
        }
    }
    static func restore(_ saved: Saved) {
        let pb = NSPasteboard.general
        pb.clearContents()
        guard !saved.isEmpty else { return }
        pb.writeObjects(saved.map { types in
            let item = NSPasteboardItem()
            for (t, data) in types { item.setData(data, forType: t) }
            return item
        })
    }
}

extension Clipboard {
    /// What Command+V attaches, as paths: files copied in Finder, else a picture with no file behind it (a screenshot taken
    /// to the clipboard, an image copied from a page), saved as a PNG first. Nil when the clipboard holds neither.
    static func pastedFiles() -> [String]? {
        let pb = NSPasteboard.general
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            return urls.map(\.path)
        }
        // Text wins: Excel, Pages and Notes put a picture of what you copied beside the words.
        guard pb.availableType(from: [.string]) == nil, pb.availableType(from: [.png, .tiff]) != nil, let image = NSImage(pasteboard: pb),
              let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return nil }
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Perch/Pasted", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        sweep(dir)
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        var url = dir.appendingPathComponent("Pasted image \(f.string(from: Date())).png")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) { url = dir.appendingPathComponent("Pasted image \(f.string(from: Date())) \(n).png"); n += 1 }
        guard (try? png.write(to: url)) != nil else { return nil }
        return [url.path]
    }

    /// Pasted pictures are kept a week, long enough for the agent to read them, then let go.
    private static func sweep(_ dir: URL) {
        let fm = FileManager.default
        let old = Date().addingTimeInterval(-7 * 86_400)
        for u in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            if let d = (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, d < old { try? fm.removeItem(at: u) }
        }
    }
}
