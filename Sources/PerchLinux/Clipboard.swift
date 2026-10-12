import CPerchLinux
import Foundation
import PerchCore

/// The clipboard (X's CLIPBOARD selection), for the paste fallback of a reply: set text, and put back what was there.
/// Setting goes through GDK, which then owns the selection and hands the text to whoever pastes, from the main loop: the
/// main thread must keep running while another app pastes. Reading the text that was there asks its owner directly on
/// Perch's own X connection (XServer), so it is synchronous without running GTK's loop inside a caller; GTK 4 only reads
/// asynchronously, and running its loop here would run other main-queue work in the middle of the controller's.
@MainActor
enum Clipboard {
    /// The text that was there, or nil when there was none (or it was not text: an image or files are not kept).
    typealias Saved = String?

    private static var clipboard: OpaquePointer? { gdk_display_get_default().flatMap { gdk_display_get_clipboard($0) } }
    /// What Perch put there last: when Perch owns the clipboard its text is this, and asking X would wait on ourselves.
    private static var ours: String?

    static func save() -> Saved {
        guard let cb = clipboard else { return nil }
        if gdk_clipboard_is_local(cb) != 0 { return ours }
        return XServer.shared.clipboardText()
    }

    /// Puts the saved text back; with nothing saved, empties the clipboard if it still holds Perch's text.
    static func restore(_ saved: Saved) {
        guard let cb = clipboard else { return }
        if let saved { set(saved); return }
        if gdk_clipboard_is_local(cb) != 0 { _ = gdk_clipboard_set_content(cb, nil); ours = nil }
    }

    static func set(_ text: String) {
        guard let cb = clipboard else { return }
        gdk_clipboard_set_text(cb, text)
        ours = text
    }

    /// When the clipboard holds files (a file manager's copy), true, and their local paths go to `done` once read (a
    /// moment later). False otherwise, so a paste goes on as text.
    static func filePaths(then done: @escaping @MainActor ([String]) -> Void) -> Bool {
        guard let cb = clipboard, let formats = gdk_clipboard_get_formats(cb) else { return false }
        // The list as the file manager wrote it, read whole without blocking (its owner answers through the main loop).
        let mimes: [String] = ["x-special/gnome-copied-files", "text/uri-list"].filter { gdk_content_formats_contain_mime_type(formats, $0) != 0 }
        guard !mimes.isEmpty else { return false }
        let read = Read(done, mimes)
        let box = Unmanaged.passRetained(read).toOpaque()
        gdk_clipboard_read_async(cb, &read.mimes, G_PRIORITY_DEFAULT, nil, { source, result, data in
            let read = Unmanaged<Read>.fromOpaque(data!).takeUnretainedValue()
            guard let stream = gdk_clipboard_read_finish(OpaquePointer(source), result, nil, nil) else { return read.finish(nil) }
            let out = g_memory_output_stream_new_resizable()
            read.out = out
            let flags = GOutputStreamSpliceFlags(rawValue: G_OUTPUT_STREAM_SPLICE_CLOSE_SOURCE.rawValue | G_OUTPUT_STREAM_SPLICE_CLOSE_TARGET.rawValue)
            g_output_stream_splice_async(cast(raw(out)), stream, flags, G_PRIORITY_DEFAULT, nil, { _, result, data in
                let read = Unmanaged<Read>.fromOpaque(data!).takeUnretainedValue()
                let out: UnsafeMutablePointer<GOutputStream> = cast(raw(read.out))
                guard g_output_stream_splice_finish(out, result, nil) >= 0, let bytes = g_memory_output_stream_steal_as_bytes(cast(raw(out))) else { return read.finish(nil) }
                var size = 0
                let text = g_bytes_get_data(bytes, &size).map { String(decoding: UnsafeRawBufferPointer(start: $0, count: size), as: UTF8.self) }
                g_bytes_unref(bytes)
                read.finish(text)
            }, data)
            g_object_unref(raw(stream))
        }, box)
        return true
    }

    /// One read of the clipboard's file list, kept alive until it ends.
    private final class Read {
        let body: @MainActor ([String]) -> Void
        var mimes: [UnsafePointer<CChar>?]
        var out: UnsafeMutablePointer<GOutputStream>?
        init(_ b: @escaping @MainActor ([String]) -> Void, _ m: [String]) { body = b; mimes = m.map { UnsafePointer(strdup($0)) } + [nil] }
        deinit { mimes.forEach { free(UnsafeMutableRawPointer(mutating: $0)) }; if let out { g_object_unref(raw(out)) } }
        /// Hands over the paths and lets go of this read.
        func finish(_ text: String?) {
            let paths = text.map(CopiedFiles.paths) ?? []
            MainActor.assumeIsolated { body(paths) }
            Unmanaged.passUnretained(self).release()
        }
    }
}

extension Clipboard {
    /// STUB: true when the clipboard offers files, whose paths then go to `done`.
    static func filePaths(then done: @escaping @MainActor ([String]) -> Void) -> Bool { false }
}
