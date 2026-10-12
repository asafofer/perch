import CPerchLinux
import Foundation

// GTK owns the main thread, so Swift's main queue (MainActor, DispatchQueue.main, Task on the main actor) is drained
// from GLib's loop. libdispatch hands CoreFoundation an eventfd that turns readable when the main queue has work; the
// same two entry points CFRunLoop uses on Linux let GLib watch it.
@_silgen_name("_dispatch_get_main_queue_handle_4CF") private func dispatchMainHandle() -> Int32
@_silgen_name("_dispatch_main_queue_callback_4CF") private func dispatchMainDrain(_ msg: UnsafeMutableRawPointer?)

enum GLoop {
    private static var running = true

    /// Runs GTK and the main queue together until `quit()`.
    static func run() {
        let fd = dispatchMainHandle()
        _ = g_unix_fd_add(fd, G_IO_IN, { fd, _, _ in
            var value: UInt64 = 0
            _ = read(fd, &value, 8)   // nonblocking eventfd: reset it, whoever reads first
            dispatchMainDrain(nil)
            return gboolean(1)
        }, nil)
        while running { g_main_context_iteration(nil, 1) }
    }

    static func quit() { running = false; g_main_context_wakeup(nil) }

    /// A repeating timer on GLib's loop, on the main thread. Return false to stop it.
    @discardableResult
    static func every(_ seconds: Double, _ body: @escaping @MainActor () -> Bool) -> UInt32 {
        let box = Unmanaged.passRetained(Box(body)).toOpaque()
        return g_timeout_add_full(G_PRIORITY_DEFAULT, guint(max(1, seconds * 1000)), { data in
            let box = Unmanaged<Box>.fromOpaque(data!).takeUnretainedValue()
            return MainActor.assumeIsolated { box.body() } ? gboolean(1) : gboolean(0)
        }, box, { data in Unmanaged<Box>.fromOpaque(data!).release() })
    }
    static func cancel(_ id: UInt32) { if id != 0 { g_source_remove(id) } }

    private final class Box { let body: @MainActor () -> Bool; init(_ b: @escaping @MainActor () -> Bool) { body = b } }
}

/// Casts between GTK's pointer types (C casts in GTK's own macros).
@inline(__always) func cast<T>(_ p: UnsafeMutableRawPointer?) -> UnsafeMutablePointer<T> { p!.assumingMemoryBound(to: T.self) }
@inline(__always) func raw<T>(_ p: UnsafeMutablePointer<T>?) -> UnsafeMutableRawPointer? { p.map { UnsafeMutableRawPointer($0) } }
@inline(__always) func raw(_ p: OpaquePointer?) -> UnsafeMutableRawPointer? { p.map { UnsafeMutableRawPointer($0) } }

/// A C string GLib allocated, as a Swift string, freed.
func takeGString(_ p: UnsafeMutablePointer<CChar>?) -> String? {
    guard let p else { return nil }
    defer { g_free(p) }
    return String(cString: p)
}
