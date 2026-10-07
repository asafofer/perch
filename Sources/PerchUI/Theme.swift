import SwiftUI
import AppKit

public enum Palette {
    public static let saffron = Color(red: 246/255, green: 185/255, blue: 59/255)
    public static let ink = Color(red: 43/255, green: 27/255, blue: 14/255)
    public static let done = Color(red: 91/255, green: 211/255, blue: 138/255)
    public static let attention = Color(red: 255/255, green: 122/255, blue: 89/255)
    public static let textPrimary = Color(white: 0.95)
    public static let textSecondary = Color(white: 0.58)
    public static let textTertiary = Color(white: 0.5)
    public static let hairline = Color.white.opacity(0.08)
    public static let rowSelected = Color.white.opacity(0.06)
    /// Tile colours for projects, picked by position.
    public static let tiles: [Color] = [
        Color(red: 246/255, green: 185/255, blue: 59/255),
        Color(red: 120/255, green: 200/255, blue: 180/255),
        Color(red: 240/255, green: 140/255, blue: 120/255),
        Color(red: 150/255, green: 160/255, blue: 235/255),
    ]
}

public enum Motion {
    /// Respect Reduce Motion: springs become short fades.
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// Opening: quick with a small, confident overshoot.
    public static var expand: Animation { reduced ? .easeOut(duration: 0.16) : .spring(response: 0.46, dampingFraction: 0.74) }
    /// Closing: settled, no wobble.
    public static var collapse: Animation { reduced ? .easeOut(duration: 0.12) : .spring(response: 0.36, dampingFraction: 0.9) }
    /// Switching content inside an open card.
    public static var snappy: Animation { reduced ? .easeOut(duration: 0.12) : .spring(response: 0.32, dampingFraction: 0.86) }
    /// The creature moving between its perch and the card.
    public static var creature: Animation { reduced ? .easeOut(duration: 0.16) : .spring(response: 0.55, dampingFraction: 0.66) }
}

/// One family (SF Pro, the system face), four weights of restraint. Roles, not sizes.
enum Typo {
    static let hero = Font.system(size: 22, weight: .semibold)
    static let body = Font.system(size: 14, weight: .regular)
    static let title = Font.system(size: 13.5, weight: .semibold)
    static let meta = Font.system(size: 12.5, weight: .regular)
    static let row = Font.system(size: 14, weight: .medium)
    static let label = Font.system(size: 12.5, weight: .medium)
    static let chip = Font.system(size: 12, weight: .medium)
    static let key = Font.system(size: 11, weight: .medium)
    static let button = Font.system(size: 13, weight: .semibold)
}
