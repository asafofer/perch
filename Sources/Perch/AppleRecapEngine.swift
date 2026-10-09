import Foundation
import FoundationModels
import PerchCore

@Generable
struct GeneratedRecap {
    @Guide(description: "What the developer was doing, taken from the conversation. Starts with You were, past tense, never 'now'. Under 60 characters.")
    var headline: String
    @Guide(description: "What the assistant did, found or changed in its last message, past tense. Not what the user asked. Under 110 characters.")
    var context: String
    @Guide(description: "The single most useful next step for the developer, taken from the latest messages. Under 60 characters. Never something the assistant already did.")
    var next: String
}

/// Writes the card's words with Apple's on-device model: free, private, offline, no sign-in.
enum AppleRecapEngine {
    /// nil when the model is ready, otherwise a plain reason (for logs and the menu).
    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(let reason): return "\(reason)"
        }
    }

    /// ready, off (Apple Intelligence switched off), downloading (model not ready yet), unsupported (this Mac can't run it)
    static var setupState: String {
        switch SystemLanguageModel.default.availability {
        case .available: return "ready"
        case .unavailable(.appleIntelligenceNotEnabled): return "off"
        case .unavailable(.modelNotReady): return "downloading"
        case .unavailable: return "unsupported"
        }
    }

    static func recap(digest: SessionDigest, git: GitInfo?, name: String, agent: String = "Claude") async -> RecapText? {
        guard unavailableReason == nil else { return nil }
        let session = LanguageModelSession(instructions: RecapPrompt.instructions)
        do {
            let r = try await session.respond(to: RecapPrompt.build(digest: digest, git: git, projectName: name, agent: agent), generating: GeneratedRecap.self)
            let c = r.content
            return RecapText(headline: c.headline.trimmingCharacters(in: .whitespacesAndNewlines), context: c.context.trimmingCharacters(in: .whitespacesAndNewlines), next: c.next.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            NSLog("Perch: on-device recap failed for \(name): \(error)")
            return nil
        }
    }
}

/// Recaps are cached by session and last activity, so each is written once.
final class RecapCache: @unchecked Sendable {
    static let shared = RecapCache()
    private let url: URL
    private var store: [String: RecapText] = [:]
    private let lock = NSLock()

    private init() {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Perch")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("recaps.json")
        if let data = try? Data(contentsOf: url), let s = try? JSONDecoder().decode([String: RecapText].self, from: data) { store = s }
    }

    static func key(for d: SessionDigest) -> String? {
        guard let id = d.sessionId, let t = d.lastTimestamp else { return nil }
        return "\(id)|\(Int(t.timeIntervalSince1970))|apple-v4"
    }
    func get(_ key: String) -> RecapText? { lock.lock(); defer { lock.unlock() }; return store[key] }
    func set(_ key: String, _ value: RecapText) {
        lock.lock(); store[key] = value
        if store.count > 200 {
            // Keep the 100 newest by the session time in the key ("id|time|version"). Dictionary order is not age.
            let time: (String) -> Int = { Int($0.split(separator: "|").dropFirst().first ?? "") ?? 0 }
            let keep = Set(store.keys.sorted { time($0) > time($1) }.prefix(100))
            store = store.filter { keep.contains($0.key) }
        }
        let data = try? JSONEncoder().encode(store); lock.unlock()
        if let data { try? data.write(to: url, options: .atomic) }
    }
}

/// Which parts of the plain recap are facts the model must not override.
enum RecapMerge {
    /// Keep the plain "next" when it came from a concrete fact: Claude's open question or uncommitted files.
    /// Any model field that isn't grounded in the conversation falls back to the plain one.
    static func apply(_ r: RecapText, to p: Project, grounding: SessionDigest? = nil) -> Project {
        // The plain next step only exists when it is a fact (a question to answer, a step the agent stated), so it wins.
        let concrete = p.status.kind == "attention" || !p.next.isEmpty
        let grounded: (String) -> Bool = { text in grounding.map { Grounding.isGrounded(text, in: $0) } ?? true }
        // A field is used only if it is the right length (never cut off), grounded in the conversation, and in the right voice.
        let oneSentence = !r.headline.dropLast().contains(".") && !r.next.dropLast().contains(".")
        let repeats = r.context.contains(r.headline) || r.headline.contains(r.context)
        var r = r
        r.next = r.next.replacingOccurrences(of: #"^\s*next\s*[:,-]\s*"#, with: "", options: [.regularExpression, .caseInsensitive])   // the card already says "Next"
        r.next = r.next.prefix(1).uppercased() + r.next.dropFirst()
        var headline = r.headline
        if !headline.hasSuffix(".") { headline += "." }
        // "You were running the check now." mixes tenses; the card is about the past.
        let headlineOK = oneSentence && r.headline.hasPrefix("You were") && (8...64).contains(r.headline.count) && grounded(r.headline)
            && r.headline.range(of: #"\bnow\b"#, options: [.regularExpression, .caseInsensitive]) == nil
        let asked = grounding?.lastAsk ?? ""
        let contextOK = !repeats && (8...120).contains(r.context.count) && grounded(r.context) && (asked.isEmpty || !Grounding.copiesUserMessage(r.context, asked))
        let nextOK = oneSentence && (4...64).contains(r.next.count) && grounded(r.next) && !Recap.isGitChore(r.next)
        return p.withRecap(RecapText(headline: headlineOK ? headline : p.headline,
                                     context: contextOK ? r.context : p.context,
                                     next: concrete || !nextOK ? p.next : r.next))
    }
}

enum Grounding {
    private static let stop: Set<String> = ["were", "that", "with", "this", "your", "from", "have", "been", "into", "than", "then", "them", "they", "will", "what", "when", "where", "which", "about", "there", "their", "also", "just", "more", "some", "only", "need", "does", "make", "made"]

    /// True when the model just parroted the plain recap's quoted message back.
    /// True when the model only repeated your own prompt back instead of saying what the agent did.
    static func copiesUserMessage(_ modelText: String, _ asked: String) -> Bool {
        let a = modelText.lowercased(), b = asked.lowercased()
        return b.contains(a) || (b.count >= 12 && a.contains(String(b.prefix(40))))
    }

    /// At least half the meaningful words of the text must appear in what the developer and Claude actually said.
    static func isGrounded(_ text: String, in d: SessionDigest) -> Bool {
        let source = (d.recent.map(\.text) + [d.title ?? ""]).joined(separator: " ").lowercased()
        let words = text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init).filter { $0.count >= 4 && !stop.contains($0) }
        guard !words.isEmpty else { return true }
        let hits = words.filter { source.contains($0) }.count
        return Double(hits) / Double(words.count) >= 0.5
    }
}
