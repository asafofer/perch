import CoreGraphics

/// Where the shortcut opens Perch and where it shows up by itself (Settings, Show Perch on). Hovering the top of a
/// screen still opens it on that screen, whatever this says.
public enum ShowOn: Equatable, Sendable {
    /// The screen the cursor is on: what Perch always did.
    case mouse
    /// The screen holding the front window of the app in front.
    case window
    /// One display, by its own id (its UUID), so plugging monitors in another order keeps the choice.
    case display(String)

    /// As kept in UserDefaults and sent by the page: "mouse", "window", or a display's id. Anything empty is the mouse.
    public init(raw: String) {
        switch raw {
        case "", "mouse": self = .mouse
        case "window": self = .window
        default: self = .display(raw)
        }
    }
    public var raw: String {
        switch self {
        case .mouse: return "mouse"
        case .window: return "window"
        case .display(let id): return id
        }
    }
}

public enum ScreenTarget {
    /// Which of these screens Perch goes to. A window off every screen, no window, or a display that is not connected
    /// gives way to the screen the cursor is on; nil only when the cursor is on none of them either.
    public static func index(for choice: ShowOn, displayIDs: [String], frames: [CGRect], mouse: CGPoint, window: CGRect?) -> Int? {
        let underMouse = ScreenPicker.index(of: mouse, in: frames)
        switch choice {
        case .mouse:
            return underMouse
        case .window:
            guard let w = window else { return underMouse }
            let areas = frames.map { f -> CGFloat in let i = f.intersection(w); return i.isNull ? 0 : i.width * i.height }
            guard let best = areas.max(), best > 0 else { return underMouse }
            return areas.firstIndex(of: best)
        case .display(let id):
            return displayIDs.firstIndex(of: id) ?? underMouse
        }
    }

    /// A rect in CoreGraphics' global space (origin at the top left of the primary display, as the window list gives it)
    /// in Cocoa's (origin at the bottom left).
    public static func cocoaRect(fromCG r: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
}
