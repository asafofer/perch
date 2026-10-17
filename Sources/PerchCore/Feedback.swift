import Foundation

/// Send feedback (the last row of Settings): what goes to the maker of Perch and how it is packed. The page shows the same
/// rules (app.js `fbBig`, `fbMailBad`); the function that receives it (feedback/api/feedback.ts) checks them again.
public enum Feedback {
    /// The most Perch sends in files, all together. A Vercel function takes 4.5 MB per request; the words and the form
    /// around them fit in what is left.
    public static let maxBytes = 4 * 1024 * 1024
    /// More files than this is not a message, it is a folder.
    public static let maxFiles = 6
    /// Words past this are cut: a log pasted whole belongs in a file.
    public static let maxCharacters = 20_000

    /// An email that looks like one: something, @, a domain with a dot, an ending of two letters or more. Loose on purpose,
    /// so an unusual address that works is never refused. Empty is fine (an email is not needed) and is not checked here.
    public static func isEmail(_ s: String) -> Bool {
        let m = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return m.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@.]{2,}$"#, options: .regularExpression) != nil
    }

    /// Which files fit, in the order they were added: each one that would take the total past `maxBytes` does not, and the
    /// ones after it still may. The same rule marks the page's chips orange.
    public static func fits(_ sizes: [Int], limit: Int = maxBytes) -> [Bool] {
        var sum = 0
        return sizes.map { b in
            if sum + b > limit { return false }
            sum += b; return true
        }
    }

    /// "Perch feedback: <the first line>", the line cut at a word near 60 characters; just "Perch feedback" when there are
    /// only files.
    public static func subject(_ text: String) -> String {
        let first = text.split(whereSeparator: \.isNewline).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        guard !first.isEmpty else { return "Perch feedback" }
        guard first.count > 60 else { return "Perch feedback: " + first }
        let cut = first.prefix(60), at = cut.lastIndex(of: " ") ?? cut.endIndex
        return "Perch feedback: " + cut[..<at].trimmingCharacters(in: .whitespaces) + "\u{2026}"
    }

    /// A file as it goes: its name, its type, its bytes.
    public struct Attachment: Equatable, Sendable {
        public let name: String, type: String, data: Data
        public init(name: String, type: String, data: Data) { self.name = name; self.type = type; self.data = data }
    }

    /// The type a file goes as, by its extension. Pictures are made smaller and go as JPEG before they get here.
    public static func type(ofExtension ext: String) -> String {
        switch ext.lowercased() {
        case "jpg", "jpeg": "image/jpeg"
        case "png": "image/png"
        case "gif": "image/gif"
        case "heic": "image/heic"
        case "pdf": "application/pdf"
        case "mov": "video/quicktime"
        case "mp4": "video/mp4"
        case "zip": "application/zip"
        case "json": "application/json"
        case "csv": "text/csv"
        case "txt", "log", "md", "swift", "js", "ts", "py", "sh", "yml", "yaml", "toml", "xml", "html", "css": "text/plain"
        default: "application/octet-stream"
        }
    }

    /// The form the function reads: `text`, `email` when you gave one, `version` and `macos` when the switch is on, and
    /// each file as `file`. multipart/form-data, so files go as their own bytes (base64 would make 4 MB into 5.3).
    public static func body(text: String, email: String?, version: String?, macOS: String?, files: [Attachment], boundary: String) -> Data {
        var d = Data()
        func line(_ s: String) { d.append(Data((s + "\r\n").utf8)) }
        func field(_ name: String, _ value: String) {
            line("--" + boundary); line("Content-Disposition: form-data; name=\"\(name)\""); line(""); line(value)
        }
        field("text", String(text.prefix(maxCharacters)))
        if let email, !email.isEmpty { field("email", email) }
        if let version { field("version", version) }
        if let macOS { field("macos", macOS) }
        for f in files {
            let name = f.name.replacingOccurrences(of: "\"", with: "'").replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
            line("--" + boundary)
            line("Content-Disposition: form-data; name=\"file\"; filename=\"\(name)\"")
            line("Content-Type: " + f.type); line("")
            d.append(f.data); line("")
        }
        line("--" + boundary + "--")
        return d
    }
}
