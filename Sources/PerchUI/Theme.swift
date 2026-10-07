import SwiftUI

public enum Palette {
    public static let saffron = Color(red: 246/255, green: 185/255, blue: 59/255)
    public static let ink = Color(red: 43/255, green: 27/255, blue: 14/255)
    public static let done = Color(red: 91/255, green: 211/255, blue: 138/255)
    public static let attention = Color(red: 255/255, green: 122/255, blue: 89/255)
    public static let textPrimary = Color(white: 0.96)
    public static let textSecondary = Color(white: 0.63)
    public static let textTertiary = Color(white: 0.47)
    public static let surface = Color(white: 0.085)
    public static let surfaceStroke = Color.white.opacity(0.07)
    public static let rowSelected = Color.white.opacity(0.085)
    /// Tile colours for projects, picked by position.
    public static let tiles: [Color] = [
        Color(red: 246/255, green: 185/255, blue: 59/255),
        Color(red: 143/255, green: 211/255, blue: 193/255),
        Color(red: 242/255, green: 165/255, blue: 143/255),
        Color(red: 169/255, green: 176/255, blue: 240/255),
    ]
}

public enum Motion {
    /// Opening: quick with a small, confident overshoot.
    public static let expand = Animation.spring(response: 0.46, dampingFraction: 0.74)
    /// Closing: settled, no wobble.
    public static let collapse = Animation.spring(response: 0.36, dampingFraction: 0.9)
    /// Switching content inside an open card.
    public static let snappy = Animation.spring(response: 0.32, dampingFraction: 0.86)
    /// The creature moving between its perch and the card.
    public static let creature = Animation.spring(response: 0.55, dampingFraction: 0.66)
}

enum Typo {
    static let band = Font.system(size: 14.5, weight: .bold, design: .rounded)
    static let bandSub = Font.system(size: 13, weight: .medium, design: .rounded)
    static let hero = Font.system(size: 24, weight: .heavy, design: .rounded)
    static let body = Font.system(size: 14.5, weight: .medium, design: .rounded)
    static let label = Font.system(size: 12, weight: .semibold, design: .rounded)
    static let strong = Font.system(size: 15, weight: .bold, design: .rounded)
    static let chip = Font.system(size: 12, weight: .semibold, design: .rounded)
    static let key = Font.system(size: 11.5, weight: .bold, design: .rounded)
    static let button = Font.system(size: 14, weight: .heavy, design: .rounded)
}
