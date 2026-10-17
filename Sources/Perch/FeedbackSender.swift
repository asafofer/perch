import AppKit
import ImageIO
import UniformTypeIdentifiers
import PerchCore

/// Send feedback (Settings, the last row). It goes to Perch's feedback function (feedback/api/feedback.ts), which emails it
/// to the maker of Perch with Reply-To set to your email; when it cannot (offline, a file too big), Email it instead opens
/// Mail with a new message and everything in it. Nothing else goes: the words, your email if you gave one, the files you
/// can see on the card, and Perch's and macOS's versions while that switch is on.
enum FeedbackSender {
    /// Where it goes. PERCH_FEEDBACK_URL points a build elsewhere (a `vercel dev` on this Mac, a preview deployment).
    static var endpoint: URL? {
        URL(string: ProcessInfo.processInfo.environment["PERCH_FEEDBACK_URL"] ?? "https://perch-feedback.vercel.app/api/feedback")
    }
    /// Who Email it instead writes to. Empty, the message opens with no one in To, for you to fill in.
    static let mailTo = ""

    /// The size a file goes at, for the page's limit: a picture's once made smaller, anything else its own.
    static func size(_ path: String) -> Int {
        if isPicture(path) { return shrunk(path)?.data.count ?? fileSize(path) }
        return fileSize(path)
    }

    /// A file as it goes. Pictures go smaller first, their longest side 2000 px as JPEG: a screenshot of a whole display
    /// is several MB as a PNG and a few hundred KB like this. One that is already smaller as it is goes as it is.
    static func attachment(_ path: String) -> Feedback.Attachment? {
        let url = URL(fileURLWithPath: path)
        if isPicture(path), let small = shrunk(path) { return small }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return .init(name: url.lastPathComponent, type: Feedback.type(ofExtension: url.pathExtension), data: data)
    }

    /// Sends it, off the main thread, and says whether it went.
    static func send(text: String, email: String, paths: [String], version: String?, macOS: String?, done: @escaping @MainActor @Sendable (Bool) -> Void) {
        guard let url = endpoint else { Task { @MainActor in done(false) }; return }
        Task.detached(priority: .userInitiated) {
            let files = paths.compactMap(attachment)
            // the page will not send what does not fit; this is the last word on it
            guard files.count == paths.count, files.count <= Feedback.maxFiles, Feedback.fits(files.map(\.data.count)).allSatisfy({ $0 }) else {
                await done(false); return
            }
            let boundary = "perch-" + UUID().uuidString
            var req = URLRequest(url: url, timeoutInterval: 30)
            req.httpMethod = "POST"
            req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            let body = Feedback.body(text: text, email: Feedback.isEmail(email) ? email.trimmingCharacters(in: .whitespaces) : nil,
                                     version: version, macOS: macOS, files: files, boundary: boundary)
            var ok = false
            do {
                let (_, response) = try await URLSession.shared.upload(for: req, from: body)
                ok = ((response as? HTTPURLResponse)?.statusCode ?? 0) / 100 == 2
                if !ok { NSLog("Perch: feedback not sent (\((response as? HTTPURLResponse)?.statusCode ?? 0))") }
            } catch { NSLog("Perch: feedback not sent: \(error.localizedDescription)") }
            await done(ok)
        }
    }

    /// Email it instead: Mail with a new message to the maker of Perch, the words, the versions and the files (as they are:
    /// Mail has no 4 MB limit). Without a mail account set up it falls back to a mailto: link, files left out.
    @MainActor
    static func mail(text: String, paths: [String], version: String?, macOS: String?) {
        var words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let version, let macOS { words += (words.isEmpty ? "" : "\n\n") + "Perch \(version), macOS \(macOS)" }
        let items: [Any] = [words] + paths.map { URL(fileURLWithPath: $0) }
        if let service = NSSharingService(named: .composeEmail), service.canPerform(withItems: items) {
            if !mailTo.isEmpty { service.recipients = [mailTo] }
            service.subject = Feedback.subject(text)
            service.perform(withItems: items); return
        }
        var c = URLComponents(); c.scheme = "mailto"; c.path = mailTo
        c.queryItems = [.init(name: "subject", value: Feedback.subject(text)), .init(name: "body", value: words)]
        if let link = c.url { NSWorkspace.shared.open(link) }
    }

    private static func isPicture(_ path: String) -> Bool {
        guard let t = UTType(filenameExtension: URL(fileURLWithPath: path).pathExtension) else { return false }
        return t.conforms(to: .image) && !t.conforms(to: .gif)   // a GIF would lose its motion
    }
    private static func fileSize(_ path: String) -> Int {
        (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }
    private static func shrunk(_ path: String) -> Feedback.Attachment? {
        let url = URL(fileURLWithPath: path)
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 2000] as CFDictionary)
        else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        let size = fileSize(path)
        if size > 0, size <= out.length, let data = try? Data(contentsOf: url) {
            return .init(name: url.lastPathComponent, type: Feedback.type(ofExtension: url.pathExtension), data: data)
        }
        return .init(name: url.deletingPathExtension().lastPathComponent + ".jpg", type: "image/jpeg", data: out as Data)
    }
}
