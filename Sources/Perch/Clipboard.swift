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
