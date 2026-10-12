import CPerchLinux
import Foundation
import PerchCore

/// Linux's NotchPanel and CardWebView in one: a borderless, see-through window at the top of the screen holding the
/// page. It is override-redirect, so no window manager decorates, moves, stacks or lists it, and it can sit 10 pt above
/// the screen's edge as the Mac panel does. Click-through is an input shape: empty while nothing is open.
/// Frames are in Cocoa's coordinates (bottom-left origin), like the shared geometry; X11.flip converts.
@MainActor
final class Panel {
    let window: UnsafeMutablePointer<GtkWidget>
    let web: UnsafeMutablePointer<GtkWidget>
    private(set) var xid: Window = 0
    /// A message from the page (webkit.messageHandlers.perch.postMessage), as JSON.
    var onMessage: (([String: Any]) -> Void)?
    /// The page finished loading.
    var onLoaded: (() -> Void)?
    private(set) var frame = CGRect.zero
    /// Whether the panel may take the keyboard (NSPanel.canBecomeKey).
    var allowsKey = false
    /// Clicks pass through to what is behind (NSWindow.ignoresMouseEvents).
    var ignoresMouseEvents = true { didSet { if oldValue != ignoresMouseEvents { applyInputShape() } } }
    var alphaValue: Double = 1 { didSet { gtk_widget_set_opacity(window, alphaValue) } }
    /// The window that had the keyboard before the panel took it, to give it back.
    private var keyFrom: Window?

    init() {
        window = gtk_window_new()
        let win: UnsafeMutablePointer<GtkWindow> = cast(raw(window))
        gtk_window_set_decorated(win, 0)
        gtk_window_set_resizable(win, 0)
        gtk_window_set_title(win, "Perch")
        let size = NotchGeometry.panelSize
        gtk_window_set_default_size(win, Int32(size.width), Int32(size.height + NotchGeometry.overscan))
        gtk_widget_add_css_class(window, "perch-panel")
        let css = gtk_css_provider_new()
        gtk_css_provider_load_from_data(css, "window.perch-panel { background: transparent; box-shadow: none; }", -1)
        gtk_style_context_add_provider_for_display(gdk_display_get_default(), OpaquePointer(css), UInt32(GTK_STYLE_PROVIDER_PRIORITY_APPLICATION))

        web = webkit_web_view_new()
        let view: UnsafeMutablePointer<WebKitWebView> = cast(raw(web))
        var clear = GdkRGBA(red: 0, green: 0, blue: 0, alpha: 0)
        webkit_web_view_set_background_color(view, &clear)
        let settings = webkit_web_view_get_settings(view)
        webkit_settings_set_allow_file_access_from_file_urls(settings, 1)
        webkit_settings_set_enable_developer_extras(settings, ProcessInfo.processInfo.environment["PERCH_TRACE"] != nil ? 1 : 0)
        webkit_settings_set_enable_back_forward_navigation_gestures(settings, 0)
        gtk_window_set_child(win, web)

        let me = Unmanaged.passUnretained(self).toOpaque()
        let ucm = webkit_web_view_get_user_content_manager(view)
        _ = webkit_user_content_manager_register_script_message_handler(ucm, "perch", nil)
        let onScript: @convention(c) (OpaquePointer?, OpaquePointer?, UnsafeMutableRawPointer?) -> Void = { _, value, data in
            guard let value, let json = takeGString(jsc_value_to_json(value, 0)),
                  let obj = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { return }
            let panel = Unmanaged<Panel>.fromOpaque(data!).takeUnretainedValue()
            MainActor.assumeIsolated { panel.onMessage?(obj) }
        }
        _ = perch_connect(raw(ucm), "script-message-received::perch", unsafeBitCast(onScript, to: GCallback.self), me)
        let onLoad: @convention(c) (OpaquePointer?, WebKitLoadEvent, UnsafeMutableRawPointer?) -> Void = { _, event, data in
            guard event == WEBKIT_LOAD_FINISHED else { return }
            let panel = Unmanaged<Panel>.fromOpaque(data!).takeUnretainedValue()
            MainActor.assumeIsolated { panel.onLoaded?() }
        }
        _ = perch_connect(raw(web), "load-changed", unsafeBitCast(onLoad, to: GCallback.self), me)
        let onFail: @convention(c) (OpaquePointer?, WebKitLoadEvent, UnsafePointer<CChar>?, UnsafeMutablePointer<GError>?, UnsafeMutableRawPointer?) -> gboolean = { _, _, uri, error, _ in
            print("Perch: the page did not load (\(uri.map { String(cString: $0) } ?? "?")): \(error.map { String(cString: $0.pointee.message) } ?? "?")")
            return 0
        }
        _ = perch_connect(raw(web), "load-failed", unsafeBitCast(onFail, to: GCallback.self), me)
        let onCrash: @convention(c) (OpaquePointer?, WebKitWebProcessTerminationReason, UnsafeMutableRawPointer?) -> Void = { _, reason, _ in
            print("Perch: the page's web process ended (\(reason.rawValue))")
        }
        _ = perch_connect(raw(web), "web-process-terminated", unsafeBitCast(onCrash, to: GCallback.self), me)
        // A file dropped on the page would open in place of the card; the controller takes drops itself.
        let noNav: @convention(c) (OpaquePointer?, UnsafeMutablePointer<WebKitPolicyDecision>?, WebKitPolicyDecisionType, UnsafeMutableRawPointer?) -> gboolean = { _, decision, type, _ in
            guard type == WEBKIT_POLICY_DECISION_TYPE_NAVIGATION_ACTION, let decision else { return 0 }
            let action = webkit_navigation_policy_decision_get_navigation_action(OpaquePointer(decision))
            let uri = webkit_uri_request_get_uri(webkit_navigation_action_get_request(action)).map { String(cString: $0) } ?? ""
            if Panel.loadedURI.map({ uri.hasPrefix($0) }) == true { return 0 }
            webkit_policy_decision_ignore(decision)
            return 1
        }
        _ = perch_connect(raw(web), "decide-policy", unsafeBitCast(noNav, to: GCallback.self), me)

        // Realized but not shown: override-redirect has to be set before the window is mapped.
        gtk_widget_realize(window)
        if let surface = gtk_native_get_surface(OpaquePointer(window)), let d = X11.display {
            xid = gdk_x11_surface_get_xid(surface)
            var attrs = XSetWindowAttributes()
            attrs.override_redirect = 1
            XChangeWindowAttributes(d, xid, UInt(CWOverrideRedirect), &attrs)
        }
        applyInputShape()
    }

    private static var loadedURI: String?

    func load(_ index: URL) {
        Panel.loadedURI = index.deletingLastPathComponent().absoluteString
        webkit_web_view_load_uri(cast(raw(web)), index.absoluteString)
    }

    func show() {
        gtk_widget_set_visible(window, 1)
        setFrame(frame)
    }

    /// Moves the panel (Cocoa coordinates). Its size is fixed: the panel's.
    func setFrame(_ f: CGRect) {
        frame = f
        guard let d = X11.display, xid != 0 else { return }
        let x = X11.flip(f)
        XMoveResizeWindow(d, xid, Int32(x.minX.rounded()), Int32(x.minY.rounded()), UInt32(f.width), UInt32(f.height))
        XRaiseWindow(d, xid)
        XFlush(d)
    }

    /// Keeps the panel above whatever came up since (override-redirect windows are stacked by nobody but themselves).
    func raise() { if let d = X11.display, xid != 0 { XRaiseWindow(d, xid); XFlush(d) } }

    // MARK: the keyboard
    var isKeyWindow: Bool {
        guard let d = X11.display, xid != 0 else { return false }
        var focus: Window = 0, revert: Int32 = 0
        XGetInputFocus(d, &focus, &revert)
        return focus == xid
    }

    /// Takes the keyboard, remembering who had it.
    func makeKey() {
        guard allowsKey, let d = X11.display, xid != 0, !isKeyWindow else { return }
        keyFrom = X11.activeWindow()
        XSetInputFocus(d, xid, Int32(RevertToPointerRoot), UInt(CurrentTime))
        XFlush(d)
        gtk_widget_grab_focus(web)
    }

    /// Gives the keyboard back to the window that had it.
    func resignKey() {
        guard isKeyWindow else { keyFrom = nil; return }
        if let w = keyFrom { X11.activate(w) } else if let w = X11.activeWindow() { X11.activate(w) }
        keyFrom = nil
    }

    // MARK: clicks
    /// Only this part of the panel takes clicks (panel coordinates, top-left origin); nil means all of it.
    var clickRect: CGRect? { didSet { if oldValue != clickRect { applyInputShape() } } }

    private func applyInputShape() {
        guard let surface = gtk_native_get_surface(OpaquePointer(window)) else { return }
        let region: OpaquePointer?
        if ignoresMouseEvents {
            region = cairo_region_create()
        } else if let r = clickRect {
            var rect = cairo_rectangle_int_t(x: Int32(r.minX), y: Int32(r.minY), width: Int32(r.width), height: Int32(r.height))
            region = cairo_region_create_rectangle(&rect)
        } else {
            var rect = cairo_rectangle_int_t(x: 0, y: 0, width: Int32(NotchGeometry.panelSize.width), height: Int32(NotchGeometry.panelSize.height + NotchGeometry.overscan))
            region = cairo_region_create_rectangle(&rect)
        }
        gdk_surface_set_input_region(surface, region)
        cairo_region_destroy(region)
    }

    // MARK: the page
    func evaluate(_ js: String) {
        webkit_web_view_evaluate_javascript(cast(raw(web)), js, -1, nil, nil, nil, nil, nil)
    }
}
