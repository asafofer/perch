import SwiftUI

public enum Palette {
    public static let saffron = Color(red: 246/255, green: 185/255, blue: 59/255)
    public static let saffronDeep = Color(red: 229/255, green: 158/255, blue: 29/255)
    public static let coral = Color(red: 232/255, green: 104/255, blue: 74/255)
    public static let cheek = Color(red: 240/255, green: 138/255, blue: 93/255)
    public static let ink = Color(red: 43/255, green: 27/255, blue: 14/255)
    public static let done = Color(red: 91/255, green: 211/255, blue: 138/255)
    public static let attention = Color(red: 255/255, green: 122/255, blue: 89/255)
    public static let textPrimary = Color(white: 0.93)
    public static let textSecondary = Color(white: 0.60)
    public static let textTertiary = Color(white: 0.47)
    public static let divider = Color(white: 0.13)
    public static let keycap = Color(white: 0.125)
    public static let rowSelected = Color(white: 0.14)
}

public enum Motion {
    /// Opening the card: a confident overshoot, like Dynamic Island.
    public static let expand = Animation.spring(response: 0.55, dampingFraction: 0.72)
    /// Closing: quick and settled, no wobble.
    public static let collapse = Animation.spring(response: 0.4, dampingFraction: 0.9)
    /// Switching content inside an open card.
    public static let snappy = Animation.spring(response: 0.34, dampingFraction: 0.86)
    /// Moving the bird between its perch and the card.
    public static let bird = Animation.spring(response: 0.62, dampingFraction: 0.64)
}

enum Typo {
    static let title = Font.system(size: 18, weight: .semibold)
    static let sub = Font.system(size: 13)
    static let body = Font.system(size: 14)
    static let label = Font.system(size: 11, weight: .medium)
    static let small = Font.system(size: 12.5)
    static let mono = Font.system(size: 11.5, design: .monospaced)
    static let key = Font.system(size: 11, weight: .medium)
}
