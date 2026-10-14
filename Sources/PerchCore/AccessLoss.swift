import Foundation

/// Accessibility Perch had, gone. macOS ties the grant to the code signature, so an update signed another way (a new
/// certificate) drops it without a word, and the switch can be turned off in System Settings. Perch remembers that it had it,
/// notices when it is gone, and says so once per loss: on the update's own What's new card when an update brought it about and
/// the card shows, otherwise in a notch row at a quiet moment. Allow keeps the row up until the switch is on, then Allowed.
public struct AccessLoss: Equatable, Sendable {
    public enum Phase: String, Encodable, Sendable { case lost, asked, granted }

    /// Perch has had Accessibility on this Mac. Kept between launches.
    public var had: Bool
    /// The build that last had it. Kept: a loss on another build came with an update.
    public var hadOn: String?
    /// This loss has been said (the row folded or was put away, or What's new carried it). Kept, so a relaunch does not say it again.
    public var said: Bool
    /// Allow was pressed during this loss: System Settings is open and the row waits for the switch.
    public private(set) var asked = false
    /// When the switch came on after Allow: Allowed shows for a moment.
    public private(set) var grantedAt: Date?
    /// Each loss while Perch runs gets its own number, so the page tells a new loss from one it already put away.
    public private(set) var losses = 0
    /// The last reading; nil until the first.
    public private(set) var trusted: Bool?

    /// How long Allowed stays on the notch.
    public static let grantedFor: TimeInterval = 4

    public init(had: Bool, hadOn: String?, said: Bool) { self.had = had; self.hadOn = hadOn; self.said = said }

    /// A reading of AXIsProcessTrusted() on `build`. Returns true when it turned on (the tap and the hotkeys need starting again).
    @discardableResult
    public mutating func observe(trusted t: Bool, build: String, now: Date) -> Bool {
        let was = trusted; trusted = t
        if t {
            if asked, was == false { grantedAt = now }
            had = true; hadOn = build; said = false; asked = false
            return was == false
        }
        if had, was != false { losses += 1 }
        return false
    }

    /// Perch had it and does not now.
    public var lost: Bool { had && trusted == false }
    /// The loss came with an update: the build that last had it is not this one.
    public func afterUpdate(build: String) -> Bool { lost && hadOn != nil && hadOn != build }

    /// Allow was pressed (on the row, or on What's new).
    public mutating func allow() { if lost { asked = true } }
    /// Said: the row folded by itself, Later put it away, or What's new carried it and was closed.
    public mutating func markSaid() { if lost { said = true; asked = false } }

    /// What the notch row says, or nil when it has nothing to say.
    public func row(now: Date) -> Phase? {
        if lost { return asked ? .asked : said ? nil : .lost }
        if let g = grantedAt, now.timeIntervalSince(g) < Self.grantedFor { return .granted }
        return nil
    }
    /// What the What's new card says. `carried`: the card showed the loss, so once the switch is on it says so in green.
    public func card(carried: Bool) -> Phase? {
        if lost { return asked ? .asked : .lost }
        return carried ? .granted : nil
    }
}
