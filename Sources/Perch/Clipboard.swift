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
        let dir = pastedDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        sweep(dir)
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        var url = dir.appendingPathComponent("Pasted image \(f.string(from: Date())).png")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) { url = dir.appendingPathComponent("Pasted image \(f.string(from: Date())) \(n).png"); n += 1 }
        guard (try? png.write(to: url)) != nil else { return nil }
        return [url.path]
    }

    static let pastedDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Perch/Pasted", isDirectory: true)

    /// The pasted pictures a message names. Its paths are written bare, or in double quotes when they hold a space.
    static func pasted(in text: String) -> [String] {
        let dir = NSRegularExpression.escapedPattern(for: pastedDir.path + "/")
        guard let re = try? NSRegularExpression(pattern: dir + "[^\"/]+?\\.png") else { return [] }
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }

    private static var letting: [String: DispatchWorkItem] = [:]
    /// Sent: the agent reads a picture once it takes the message, which may wait while it works, so the file goes a while later.
    @MainActor static func letGo(_ text: String, after: TimeInterval = 600) {
        for path in pasted(in: text) {
            letting[path]?.cancel()
            let w = DispatchWorkItem { letting[path] = nil; try? FileManager.default.removeItem(atPath: path) }
            letting[path] = w
            DispatchQueue.main.asyncAfter(deadline: .now() + after, execute: w)
        }
    }
    /// Not sent after all (a new session that did not start gives your words back as the draft): the pictures stay.
    @MainActor static func keep(_ text: String) {
        for path in pasted(in: text) { letting.removeValue(forKey: path)?.cancel() }
    }

    /// Whatever a send left behind (Perch quit before letting go, a message that never went) goes after a day.
    private static func sweep(_ dir: URL) {
        let fm = FileManager.default
        let old = Date().addingTimeInterval(-86_400)
        for u in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            if let d = (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, d < old { try? fm.removeItem(at: u) }
        }
    }
}
