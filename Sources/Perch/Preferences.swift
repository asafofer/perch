import Foundation

/// What Perch remembers between launches.
enum Prefs {
    private static let d = UserDefaults.standard
    static var onboarded: Bool { get { d.bool(forKey: "onboarded") } set { d.set(newValue, forKey: "onboarded") } }
    /// Set when Perch restarts itself in the middle of setup, so it picks up at the same step.
    static var resumeStep: Int? {
        get { d.object(forKey: "resumeStep") as? Int }
        set { if let v = newValue { d.set(v, forKey: "resumeStep") } else { d.removeObject(forKey: "resumeStep") } }
    }
    static var shape: String { get { d.string(forKey: "character.shape") ?? "ears" } set { d.set(newValue, forKey: "character.shape") } }
    static var color: String { get { d.string(forKey: "character.color") ?? "#F5B83D" } set { d.set(newValue, forKey: "character.color") } }
}
