import Foundation

/// The pull requests a session opened, found in its own log: the address a `gh pr create` printed. Only the Claude app lists
/// them itself (`prs`), so for Claude Code in a terminal, Codex, pi and OpenCode this is where they come from. Their state is not
/// in the log: they show once GitHub has been asked (Checks).
public enum PullRequestScan {
    static let create = "gh pr " + "create"
    /// The ids a call carries in a log line: Claude Code's `id` and `tool_use_id`, Codex's `call_id`, pi's `toolCallId`,
    /// OpenCode's `callID`.
    private static let ids = try! NSRegularExpression(pattern: #""(?:id|call_id|tool_use_id|toolCallId|callID)"\s*:\s*"([^"]+)""#)
    /// An address that ends what was printed: the command prints the new pull request's address last, so a line of output that only
    /// mentions one (a grep over docs, a list) is not it. The address is followed by the end of the string, after any newlines.
    private static let urls = try! NSRegularExpression(pattern: #"https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[0-9]+(?=(?:\\+n|\\+r|\s)*[\"'\]}])"#)

    /// Reads a log as it grows: what a line says about a call is kept until its result comes.
    public struct Reader: Sendable {
        var pending = Set<String>()
        public private(set) var found: [String] = []
        public init() {}

        /// One line of a log (JSON, one record). A command that makes a pull request marks its call; the result that answers that
        /// call, with an address in it, is the pull request. An address in a user's message, a document or an unrelated result
        /// is never taken.
        public mutating func feed(_ line: String) {
            let hasCreate = line.contains(PullRequestScan.create), hasURL = line.contains("/pull/")
            guard hasCreate || hasURL else { return }
            let range = NSRange(line.startIndex..., in: line)
            let callIds = PullRequestScan.ids.matches(in: line, range: range).compactMap { m in Range(m.range(at: 1), in: line).map { String(line[$0]) } }
            if hasCreate && !hasURL { pending.formUnion(callIds); return }
            if hasCreate && hasURL && line.contains("\"callID\"") { pending.formUnion(callIds) }   // a call and its answer in one record (OpenCode)
            guard hasURL, let hit = callIds.first(where: { pending.contains($0) }) else { return }
            for m in PullRequestScan.urls.matches(in: line, range: range) {
                if let r = Range(m.range, in: line) { let u = String(line[r]); if !found.contains(u) { found.append(u) } }
            }
            pending.remove(hit)
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var readers: [String: (offset: UInt64, reader: Reader)] = [:]

    /// The pull requests the log at `url` shows were made, in order. A log only grows, so each read picks up where the last
    /// stopped; one that shrank is read again.
    public static func created(in url: URL) -> [String] {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.uint64Value else { return [] }
        lock.lock(); var state = readers[url.path] ?? (0, Reader()); lock.unlock()
        if size < state.offset { state = (0, Reader()) }
        if size > state.offset, let h = try? FileHandle(forReadingFrom: url) {
            defer { try? h.close() }
            try? h.seek(toOffset: state.offset)
            // In pieces, whole lines only: a line still being written is read next time.
            var carry = Data()
            while let chunk = try? h.read(upToCount: 4 << 20), !chunk.isEmpty {
                carry.append(chunk)
                guard let nl = carry.lastIndex(of: 10) else { continue }
                let whole = carry[carry.startIndex...nl]
                if whole.range(of: Data("/pull/".utf8)) != nil || whole.range(of: Data(create.utf8)) != nil {
                    for line in String(decoding: whole, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: true) { state.reader.feed(String(line)) }
                }
                state.offset += UInt64(whole.count)
                carry = Data(carry[carry.index(after: nl)...])
            }
        }
        lock.lock(); readers[url.path] = state; if readers.count > 400 { readers = Dictionary(uniqueKeysWithValues: readers.prefix(200).map { ($0.key, $0.value) }) }; lock.unlock()
        return state.reader.found
    }

    /// Pull requests from their addresses, state not known: they show once GitHub has answered.
    public static func requests(_ urls: [String]) -> [PullRequest] {
        urls.compactMap { u in
            guard PullRequests.isGitHub(u), let n = Int(u.split(separator: "/").last ?? "") else { return nil }
            var p = PullRequest(number: n, repo: PullRequests.repoOf(u) ?? "", url: u, state: .open)
            p.stateKnown = false
            return p
        }
    }
}
