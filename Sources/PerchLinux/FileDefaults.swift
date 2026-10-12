import Foundation

/// Prefs' store on Linux: ~/.config/perch/settings.json. Foundation's UserDefaults there has no bundle to file an app's
/// settings under and kept nothing between launches. The part of UserDefaults' API Prefs uses, written through on every
/// change (settings change rarely; "seen" a few times a minute at most). Data is kept as base64 under {"$data": ...}.
final class FileDefaults: @unchecked Sendable {
    static let shared = FileDefaults(url: HookInstaller.dir.appendingPathComponent("settings.json"))

    private let url: URL
    private let lock = NSLock()
    private var values: [String: Any]

    init(url: URL) {
        self.url = url
        values = (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
    }

    func object(forKey key: String) -> Any? {
        lock.lock(); defer { lock.unlock() }
        guard let v = values[key] else { return nil }
        if let wrapped = v as? [String: Any], wrapped.count == 1, let b64 = wrapped["$data"] as? String { return Data(base64Encoded: b64) }
        return v
    }
    func bool(forKey key: String) -> Bool { (object(forKey: key) as? NSNumber)?.boolValue ?? (object(forKey: key) as? Bool) ?? false }
    func integer(forKey key: String) -> Int { (object(forKey: key) as? NSNumber)?.intValue ?? (object(forKey: key) as? Int) ?? 0 }
    func string(forKey key: String) -> String? { object(forKey: key) as? String }
    func data(forKey key: String) -> Data? { object(forKey: key) as? Data }
    func array(forKey key: String) -> [Any]? { object(forKey: key) as? [Any] }
    func stringArray(forKey key: String) -> [String]? { (object(forKey: key) as? [Any])?.compactMap { $0 as? String } }
    func dictionary(forKey key: String) -> [String: Any]? { object(forKey: key) as? [String: Any] }

    func set(_ value: Any?, forKey key: String) {
        guard let value else { removeObject(forKey: key); return }
        lock.lock()
        values[key] = (value as? Data).map { ["$data": $0.base64EncodedString()] } ?? value
        save()
        lock.unlock()
    }
    func removeObject(forKey key: String) {
        lock.lock(); values[key] = nil; save(); lock.unlock()
    }

    /// Called under the lock. Atomic, so a crash mid-write leaves the last good file.
    private func save() {
        guard JSONSerialization.isValidJSONObject(values),
              let data = try? JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
