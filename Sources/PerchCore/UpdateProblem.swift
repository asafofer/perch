import Foundation

/// Why an update did not go through, in Perch's own words: a line for the notch, a few words for Settings, and what you can do.
/// Sparkle's errors are plain codes in a domain; this reads them (and the errors underneath: a download that failed because
/// the Mac is offline arrives as Sparkle's own error with the network's one inside), so it needs no Sparkle and can be tested.
public struct UpdateProblem: Equatable, Sendable {
    public enum Fix: String, Sendable { case retry, move, none }

    /// One line for the notch, with what to do.
    public var line: String
    /// A few words for Settings, beside Updates.
    public var short: String
    /// Try again, move Perch to Applications (Show in Finder), or nothing you can press.
    public var fix: Fix
    /// "check" when it could not look for an update, "update" when it could not get or put one in.
    public var during: String

    public init(line: String, short: String, fix: Fix, during: String) { self.line = line; self.short = short; self.fix = fix; self.during = during }

    /// An error and the ones beneath it (`NSUnderlyingErrorKey`), outermost first.
    public struct ErrorRef: Equatable, Sendable {
        public var domain: String, code: Int
        public init(domain: String, code: Int) { self.domain = domain; self.code = code }
    }

    static let sparkle = "SUSparkleErrorDomain"
    /// The network gave out: no connection, a timeout, a lost or refused connection, no host, roaming, a secure connection that failed.
    static let offline: Set<Int> = [-1009, -1001, -1004, -1003, -1005, -1018, -1020, -1200, -1202, -1017]

    /// `updating`: Perch had an update in hand (offered, downloading, ready or restarting) rather than looking for one.
    public static func classify(_ chain: [ErrorRef], updating: Bool) -> UpdateProblem {
        let during = updating ? "update" : "check"
        if chain.contains(where: { $0.domain == NSURLErrorDomain && offline.contains($0.code) }) {
            return UpdateProblem(line: "No internet connection. Try again in a moment.", short: "no connection", fix: .retry, during: during)
        }
        guard let code = chain.first(where: { $0.domain == sparkle })?.code else { return generic(during) }
        switch code {
        case 1005, 1003:   // running translocated, or from a disk image or another read-only place
            return UpdateProblem(line: "Move Perch to Applications, then open it again.", short: "move Perch to Applications", fix: .move, during: "update")
        case 1000, 1002, 1004, 1007:   // the feed would not read
            return UpdateProblem(line: "Perch couldn\u{2019}t read the list of versions. Try again later.", short: "couldn\u{2019}t check", fix: .retry, during: "check")
        case 2000, 2001:
            return UpdateProblem(line: "The download didn\u{2019}t finish. Try again.", short: "couldn\u{2019}t download", fix: .retry, during: "update")
        case 3000, 3001, 3002, 4009:
            return UpdateProblem(line: "The update didn\u{2019}t pass its safety check, so Perch left it alone.", short: "couldn\u{2019}t verify", fix: .retry, during: "update")
        case 4000, 4012:   // no room to write over itself here
            return UpdateProblem(line: "Perch can\u{2019}t replace itself in this folder. Move it to Applications.", short: "can\u{2019}t update here", fix: .move, during: "update")
        case 4004:
            return UpdateProblem(line: "Perch updated but couldn\u{2019}t reopen. Open it again.", short: "open Perch again", fix: .none, during: "update")
        case 4001, 4002, 4003, 4005, 4006, 4007, 4008, 4010:
            return UpdateProblem(line: "The update could not be installed. Try again.", short: "couldn\u{2019}t install", fix: .retry, during: "update")
        default:
            return generic(during)
        }
    }

    /// Sparkle's `SPUNoUpdateFoundReason`: only the two that mean this Mac cannot run what the feed offers are a problem.
    /// `minimumOS` is what the newest release asks for, when the feed says.
    public static func noUpdate(reason: Int, minimumOS: String? = nil) -> UpdateProblem? {
        switch reason {
        case 5:   // an Intel Mac
            return UpdateProblem(line: "This version needs an Apple silicon Mac.", short: "needs Apple silicon", fix: .none, during: "check")
        case 3:   // macOS too old
            let os = minimumOS.flatMap { $0.isEmpty ? nil : "macOS \($0)" } ?? "a newer macOS"
            return UpdateProblem(line: "This version needs \(os) or later.", short: minimumOS.map { "needs macOS \($0)" } ?? "needs newer macOS", fix: .none, during: "check")
        default:
            return nil
        }
    }

    /// Perch could not quit to let the update in.
    public static let couldNotQuit = UpdateProblem(line: "Perch couldn\u{2019}t quit to finish updating. Try again.", short: "couldn\u{2019}t quit", fix: .retry, during: "update")

    static func generic(_ during: String) -> UpdateProblem {
        UpdateProblem(line: during == "update" ? "The update didn\u{2019}t go through. Try again." : "Perch couldn\u{2019}t check for updates. Try again.",
                      short: during == "update" ? "couldn\u{2019}t update" : "couldn\u{2019}t check", fix: .retry, during: during)
    }
}
