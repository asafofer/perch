import CPerchLinux
import Foundation

// OWNER: the sessions agent. STUB.
/// inotify over the session folders (recursive, new subfolders included), Linux's FSEvents: `onChange` on the main
/// thread when anything under them is written, created or moved.
@MainActor
final class Watcher {
    var onChange: (() -> Void)?
    init(paths: [String]) {}
    func start() {}
}
