import Foundation
import PerchCore

/// The process table, from /proc. Other users' processes show their stat but not their executable, folder or
/// environment, which is fine: the agents Perch looks for are yours. Safe on any thread.
enum Proc {
    /// Every process's /proc/<pid>/stat, by pid.
    static func table() -> [pid_t: ProcStat] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: "/proc") else { return [:] }
        var out: [pid_t: ProcStat] = [:]
        for n in names {
            guard let pid = pid_t(n), let s = stat(pid) else { continue }
            out[pid] = s
        }
        return out
    }

    static func stat(_ pid: pid_t) -> ProcStat? { read("/proc/\(pid)/stat").flatMap { ProcStat.parse(String(decoding: $0, as: UTF8.self)) } }
    static func exe(_ pid: pid_t) -> String? { link("/proc/\(pid)/exe").map(ProcessArgs.liveExecutable) }
    static func cwd(_ pid: pid_t) -> String? { link("/proc/\(pid)/cwd") }

    /// argv and the environment the process started with.
    static func args(_ pid: pid_t, executable: String) -> ProcessArgs? {
        guard let cmd = read("/proc/\(pid)/cmdline") else { return nil }
        return ProcessArgs.parse(cmdline: cmd, environ: read("/proc/\(pid)/environ") ?? Data(), executable: executable)
    }

    /// When the process started, from its clock ticks after boot.
    static func started(_ s: ProcStat) -> Date { bootTime.addingTimeInterval(Double(s.startTicks) / ticks) }
    private static let ticks = Double(max(1, sysconf(Int32(_SC_CLK_TCK))))
    private static let bootTime: Date = {
        let text = read("/proc/stat").map { String(decoding: $0, as: UTF8.self) } ?? ""
        let line = text.split(separator: "\n").first { $0.hasPrefix("btime ") }
        return Date(timeIntervalSince1970: line.flatMap { Double($0.dropFirst(6).trimmingCharacters(in: .whitespaces)) } ?? 0)
    }()

    /// A file read to its end. /proc's files say they are empty, so their size cannot be trusted.
    static func read(_ path: String) -> Data? {
        let fd = open(path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var out = Data(), buf = [UInt8](repeating: 0, count: 8192)
        while true {
            let n = buf.withUnsafeMutableBytes { Foundation.read(fd, $0.baseAddress, 8192) }
            if n < 0 { return errno == EINTR ? nil : (out.isEmpty ? nil : out) }
            if n == 0 { return out }
            out.append(contentsOf: buf[0..<n])
        }
    }

    static func link(_ path: String) -> String? {
        var buf = [CChar](repeating: 0, count: 4097)
        let n = readlink(path, &buf, 4096)
        guard n > 0 else { return nil }
        return String(decoding: buf[0..<n].map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// A program on PATH, or in the places a desktop session's PATH often leaves out (~/.local/bin, ~/.cargo/bin).
    static func which(_ name: String) -> String? {
        if name.hasPrefix("/") { return FileManager.default.isExecutableFile(atPath: name) ? name : nil }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dirs = (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin").split(separator: ":").map(String.init)
            + [home + "/.local/bin", home + "/.cargo/bin", "/usr/local/bin", "/usr/bin", "/snap/bin", "/home/linuxbrew/.linuxbrew/bin"]
        return dirs.lazy.map { $0 + "/" + name }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
