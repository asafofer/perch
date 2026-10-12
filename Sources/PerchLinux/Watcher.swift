import CPerchLinux
import Foundation

/// inotify over the session folders, Linux's FSEvents: `onChange` on the main thread when anything under them is written,
/// created, moved or deleted. inotify watches one folder at a time, so a tree gets a watch per folder, and each new
/// subfolder (Codex's folder for a new day) gets its own as it appears. A folder that does not exist yet (an agent
/// installed later) is waited for from the nearest one that does. The controller spaces the refreshes.
@MainActor
final class Watcher {
    var onChange: (() -> Void)?

    /// The trees Perch reads sessions from.
    static var sessionTrees: [String] { [".claude/projects", ".codex/sessions", ".pi/agent/sessions"].map { SessionHome.path + "/" + $0 } }
    /// OpenCode's folder is watched alone, not its tree: its database and the WAL beside it sit at the top, and the old
    /// storage/ below can hold tens of thousands of folders.
    static var sessionFolders: [String] { [SessionHome.path + "/.local/share/opencode"] }

    private enum Kind { case tree, flat, ancestor }
    private struct Watch { let path: String; let kind: Kind }
    private let trees: [String], flats: [String]
    private var fd: Int32 = -1
    private var source: guint = 0
    private var watches: [Int32: Watch] = [:]
    private var full = false
    /// How many folders are watched (not counting the ones waited on for a folder yet to come).
    var count: Int { watches.values.filter { $0.kind != .ancestor }.count }

    /// Every session folder of every agent.
    convenience init() { self.init(paths: Self.sessionTrees, flat: Self.sessionFolders) }

    /// `paths` are watched with everything under them, `flat` only themselves.
    init(paths: [String], flat: [String] = []) {
        trees = paths.map { ($0 as NSString).standardizingPath }
        flats = flat.map { ($0 as NSString).standardizingPath }
    }

    func start() {
        guard fd < 0 else { return }
        fd = inotify_init1(Int32(IN_NONBLOCK) | Int32(IN_CLOEXEC))
        guard fd >= 0 else { print("perch: inotify: \(String(cString: strerror(errno)))"); return }
        attach()
        let me = Unmanaged.passRetained(self).toOpaque()
        source = g_unix_fd_add_full(G_PRIORITY_DEFAULT, fd, G_IO_IN, { _, _, data in
            let me = Unmanaged<Watcher>.fromOpaque(data!).takeUnretainedValue()
            return MainActor.assumeIsolated { me.drain() } ? gboolean(1) : gboolean(0)
        }, me, { data in Unmanaged<Watcher>.fromOpaque(data!).release() })
    }

    func stop() {
        if source != 0 { g_source_remove(source); source = 0 }
        if fd >= 0 { close(fd); fd = -1 }
        watches = [:]
    }

    private static let changes = UInt32(IN_MODIFY) | UInt32(IN_CREATE) | UInt32(IN_DELETE) | UInt32(IN_MOVED_FROM) | UInt32(IN_MOVED_TO)
        | UInt32(IN_DELETE_SELF) | UInt32(IN_MOVE_SELF) | UInt32(IN_ONLYDIR)
    private static let arrivals = UInt32(IN_CREATE) | UInt32(IN_MOVED_TO) | UInt32(IN_ONLYDIR)

    /// Watches each root that exists (and is not watched yet), and the nearest existing folder above each that does not.
    private func attach() {
        let watched = Set(watches.values.filter { $0.kind != .ancestor }.map(\.path))
        for (root, kind) in trees.map({ ($0, Kind.tree) }) + flats.map({ ($0, Kind.flat) }) where !watched.contains(root) {
            if isFolder(root) {
                if kind == .tree { addTree(root) } else { add(root, .flat) }
            } else {
                var up = (root as NSString).deletingLastPathComponent
                while up.count > 1, !isFolder(up) { up = (up as NSString).deletingLastPathComponent }
                add(up, .ancestor)
            }
        }
        // Ancestors no longer on the way to a missing root are let go.
        let missing = (trees + flats).filter { !isFolder($0) }
        for (wd, w) in watches where w.kind == .ancestor && !missing.contains(where: { $0.hasPrefix(w.path == "/" ? "/" : w.path + "/") }) {
            inotify_rm_watch(fd, wd); watches[wd] = nil
        }
    }

    @discardableResult
    private func add(_ path: String, _ kind: Kind) -> Bool {
        guard !full else { return false }
        let wd = inotify_add_watch(fd, path, kind == .ancestor ? Self.arrivals | UInt32(IN_MASK_ADD) : Self.changes)
        if wd < 0 {
            // The system's limit (fs.inotify.max_user_watches): the folders watched so far still work.
            if errno == ENOSPC { full = true; print("perch: out of inotify watches; raise fs.inotify.max_user_watches") }
            return false
        }
        if let had = watches[wd], had.kind != .ancestor, kind == .ancestor { return true }   // already watched for changes
        watches[wd] = Watch(path: path, kind: kind)
        return true
    }

    /// A folder and every folder under it. Links are not followed.
    private func addTree(_ path: String) {
        var stack = [path]
        while let dir = stack.popLast() {
            guard add(dir, .tree) else { continue }
            for name in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] {
                let sub = dir + "/" + name
                if isFolder(sub, followLinks: false) { stack.append(sub) }
            }
        }
    }

    private func isFolder(_ path: String, followLinks: Bool = true) -> Bool {
        var st = stat()
        guard (followLinks ? stat(path, &st) : lstat(path, &st)) == 0 else { return false }
        return (st.st_mode & S_IFMT) == S_IFDIR
    }

    /// Reads every event waiting, then says once that something changed. False stops the source (the fd is gone).
    private func drain() -> Bool {
        guard fd >= 0 else { return false }
        var changed = false, reattach = false
        let size = 64 * 1024
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 8)
        defer { buffer.deallocate() }
        while true {
            let n = read(fd, buffer, size)
            if n <= 0 { break }
            var at = 0
            while at + 16 <= n {
                let wd = buffer.loadUnaligned(fromByteOffset: at, as: Int32.self)
                let mask = buffer.loadUnaligned(fromByteOffset: at + 4, as: UInt32.self)
                let len = Int(buffer.loadUnaligned(fromByteOffset: at + 12, as: UInt32.self))
                let name = len > 0 ? String(cString: buffer.advanced(by: at + 16).assumingMemoryBound(to: CChar.self)) : ""
                at += 16 + len
                if mask & UInt32(IN_Q_OVERFLOW) != 0 { changed = true; continue }
                guard let w = watches[wd] else { continue }
                if mask & UInt32(IN_IGNORED) != 0 {
                    // The folder went away. A root that did is waited for again.
                    watches[wd] = nil
                    if w.kind != .ancestor, (trees + flats).contains(w.path) { reattach = true }
                    continue
                }
                switch w.kind {
                case .ancestor:
                    if mask & UInt32(IN_ISDIR) != 0 { reattach = true }
                case .tree:
                    changed = true
                    if mask & UInt32(IN_ISDIR) != 0, mask & (UInt32(IN_CREATE) | UInt32(IN_MOVED_TO)) != 0, !name.isEmpty { addTree(w.path + "/" + name) }
                case .flat:
                    // SQLite's shared-memory file changes when anyone reads, Perch included.
                    if !name.hasSuffix("-shm") { changed = true }
                }
            }
        }
        if reattach {
            let before = count
            attach()
            if count > before { changed = true }   // a session folder appeared, maybe with sessions already in it
        }
        if changed { onChange?() }
        return true
    }
}
