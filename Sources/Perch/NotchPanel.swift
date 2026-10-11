import AppKit
import WebKit

/// Borderless panel that floats above the menu bar on every Space and never activates the app.
final class NotchPanel: NSPanel {
    var allowsKey = false
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        animationBehavior = .none
    }
}

/// The card's web view. A file dragged from Finder onto the card goes into the reply as its path; left to WebKit, it
/// would open the file in place of the card. Anything else dragged (text) is WebKit's as usual.
final class CardWebView: WKWebView {
    /// Whether the card can take files now (a card with a reply showing or on offer).
    var takesFiles: () -> Bool = { false }
    /// The dropped files' paths. False when they had nowhere to go.
    var onFiles: ([String]) -> Bool = { _ in false }
    /// Files over the card: how many, and where the pointer is in the page (top left origin). 0 when they go away.
    var onDrag: (Int, CGPoint) -> Void = { _, _ in }
    private var dragSent: (Int, CGPoint)?

    /// A card without the keyboard (hovered open, or opened by Perch) answers the first click. WebKit would spend it taking
    /// the keyboard, so Reply or Pick up needed a second click.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func files(_ info: NSDraggingInfo?) -> [String]? {
        guard let urls = info?.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else { return nil }
        return urls.map(\.path)
    }
    override func draggingEntered(_ info: NSDraggingInfo) -> NSDragOperation {
        guard let paths = files(info) else { return super.draggingEntered(info) }
        return over(info, paths.count)
    }
    override func draggingUpdated(_ info: NSDraggingInfo) -> NSDragOperation {
        guard let paths = files(info) else { return super.draggingUpdated(info) }
        return over(info, paths.count)
    }
    override func draggingExited(_ info: NSDraggingInfo?) {
        guard files(info) != nil else { super.draggingExited(info); return }
        tell(0, .zero)
    }
    /// Files over the card: the page lights the reply up for them, and takes them where the pointer is.
    private func over(_ info: NSDraggingInfo, _ count: Int) -> NSDragOperation {
        guard takesFiles() else { tell(0, .zero); return [] }
        let p = convert(info.draggingLocation, from: nil)
        tell(count, CGPoint(x: p.x, y: isFlipped ? p.y : bounds.height - p.y))
        return .copy
    }
    /// Only what changed: a drag sends updates many times a second, moving or not.
    private func tell(_ count: Int, _ at: CGPoint) {
        if count == 0 { guard dragSent != nil else { return }; dragSent = nil; onDrag(0, .zero); return }
        if let s = dragSent, s.0 == count, s.1 == at { return }
        dragSent = (count, at); onDrag(count, at)
    }
    override func prepareForDragOperation(_ info: NSDraggingInfo) -> Bool { files(info) == nil ? super.prepareForDragOperation(info) : takesFiles() }
    override func performDragOperation(_ info: NSDraggingInfo) -> Bool {
        guard let paths = files(info) else { return super.performDragOperation(info) }
        dragSent = nil
        return onFiles(paths)
    }
    override func concludeDragOperation(_ info: NSDraggingInfo?) { if files(info) == nil { super.concludeDragOperation(info) } }
}
