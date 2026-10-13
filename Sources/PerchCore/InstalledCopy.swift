import Foundation

/// A test build's way back: which other copy of Perch on this Mac is the installed one. Every copy has the same bundle id,
/// so Launch Services lists them all; a build (a worktree's build/, SwiftPM's .build, Xcode's DerivedData) or one in the
/// Trash is not installed, and the one running is never the way back. Applications (the Mac's, then your own) comes first;
/// a copy left where it was unzipped still counts.
public enum InstalledCopy {
    public static func pick(_ found: [URL], running: URL) -> URL? {
        let here = running.standardizedFileURL.path
        let copies = found.map { $0.standardizedFileURL }.filter { url in
            let p = url.path
            return p != here && !["/build/", "/.build/", "/DerivedData/", "/.Trash/"].contains { p.contains($0) }
        }
        func rank(_ u: URL) -> Int { u.path.hasPrefix("/Applications/") ? 0 : u.path.contains("/Applications/") ? 1 : 2 }
        return copies.min { rank($0) < rank($1) }
    }
}
