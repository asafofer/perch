/// Shortcuts are written in Latin letters (R, N, A, D, Command+comma, Command+V). On a layout without them (Hebrew, Arabic,
/// Cyrillic...) the key types another character, so those fall back to the key's place on a US keyboard.
public enum KeyLayout {
    private static let usPosition: [UInt16: String] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e",
        15: "r", 16: "y", 17: "t", 31: "o", 32: "u", 34: "i", 35: "p", 37: "l", 38: "j", 40: "k", 45: "n", 46: "m",
        41: ";", 43: ",", 44: "/", 47: ".",
    ]

    /// The shortcut character for a key: what it types when that is Latin (so Dvorak and AZERTY keep their own letters),
    /// otherwise its US-position character.
    public static func shortcut(typed: String?, keyCode: UInt16) -> String {
        let t = (typed ?? "").lowercased()
        if t.unicodeScalars.count == 1, let s = t.unicodeScalars.first, s.isASCII, s.value > 0x20, s.value < 0x7F { return t }   // not a control code: Control+Q types U+0011
        return usPosition[keyCode] ?? t
    }
}
