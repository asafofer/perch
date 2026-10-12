import CPerchLinux
import Foundation

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
        let fileList = gdk_file_list_get_type()
        guard gdk_content_formats_contain_gtype(formats, fileList) != 0
                || gdk_content_formats_contain_mime_type(formats, "text/uri-list") != 0
                || gdk_content_formats_contain_mime_type(formats, "x-special/gnome-copied-files") != 0 else { return false }
        let box = Unmanaged.passRetained(Done(done)).toOpaque()
        gdk_clipboard_read_value_async(cb, fileList, G_PRIORITY_DEFAULT, nil, { source, result, data in
            let done = Unmanaged<Done>.fromOpaque(data!).takeRetainedValue()
            var paths: [String] = []
            if let value = gdk_clipboard_read_value_finish(OpaquePointer(source), result, nil),
               let list = g_value_get_boxed(value) {
                var node = gdk_file_list_get_files(OpaquePointer(list))
                let head = node
                while let n = node {
                    if let path = takeGString(g_file_get_path(OpaquePointer(n.pointee.data))) { paths.append(path) }
                    node = n.pointee.next
                }
                g_slist_free(head)
            }
            MainActor.assumeIsolated { done.body(paths) }
        }, box)
        return true
    }
    private final class Done { let body: @MainActor ([String]) -> Void; init(_ b: @escaping @MainActor ([String]) -> Void) { body = b } }
}
