import Foundation
import FoundationModels
import PerchCore

@Generable
struct GeneratedRecap {
    @Guide(description: "What the developer was doing. Second person, past tense, under 60 characters, ends with a period.")
    var headline: String
    @Guide(description: "The key decision or where things stand now, under 110 characters.")
    var context: String
    @Guide(description: "The single most useful next step, imperative, under 60 characters. Never something already done.")
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

    static func recap(digest: SessionDigest, git: GitInfo?, name: String) async -> RecapText? {
        guard unavailableReason == nil else { return nil }
        let session = LanguageModelSession(instructions: RecapPrompt.instructions)
        do {
            let r = try await session.respond(to: RecapPrompt.build(digest: digest, git: git, projectName: name), generating: GeneratedRecap.self)
            let c = r.content
            return RecapText(headline: Recap.clip(c.headline, 70), context: Recap.clip(c.context, 120), next: Recap.clip(c.next, 70))
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
        return "\(id)|\(Int(t.timeIntervalSince1970))|apple-v1"
    }
    func get(_ key: String) -> RecapText? { lock.lock(); defer { lock.unlock() }; return store[key] }
    func set(_ key: String, _ value: RecapText) {
        lock.lock(); store[key] = value
        if store.count > 200 { store = Dictionary(uniqueKeysWithValues: store.suffix(100).map { ($0.key, $0.value) }) }
        let data = try? JSONEncoder().encode(store); lock.unlock()
        if let data { try? data.write(to: url, options: .atomic) }
    }
}

/// Which parts of the plain recap are facts the model must not override.
enum RecapMerge {
    /// Keep the plain "next" when it came from a concrete fact: Claude's open question or uncommitted files.
    static func apply(_ r: RecapText, to p: Project) -> Project {
        let concrete = p.status.kind == "attention" || p.next.hasPrefix("Review ") || p.next.hasPrefix("Answer")
        return p.withRecap(RecapText(headline: r.headline, context: r.context, next: concrete ? p.next : r.next))
    }
}
