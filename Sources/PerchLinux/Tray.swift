import CPerchLinux
import Foundation

/// The menu-bar item's Linux twin: a StatusNotifierItem on the session bus, with Perch's menu over com.canonical.dbusmenu.
/// Panels that show these: Xfce's Status Tray (systray) and Indicator plugins, KDE, LXQt, Cinnamon, MATE's
/// indicator applet, waybar; GNOME only with the AppIndicator extension. Plain GDBus: libayatana-appindicator is GTK 3
/// and cannot share a process with GTK 4. A panel restarted later finds the item again (the watcher is watched).
@MainActor
final class Tray {
    struct Item {
        let title: String
        let action: () -> Void
        /// A line that only says something (a test build's name), greyed.
        var enabled = true
    }
    private var items: [Item?]
    private var revision: UInt32 = 1
    /// ARGB32 images, big-endian, largest last.
    private var pixmaps: [(w: Int32, h: Int32, argb: [UInt8])] = Tray.dome
    private let busName = "org.kde.StatusNotifierItem-\(getpid())-1"
    private static let itemPath = "/StatusNotifierItem", menuPath = "/MenuBar"
    private let bus = DBus.session

    init(items: [Item?]) {   // nil is a separator
        self.items = items
        guard let bus else { print("perch: no session bus, no tray icon"); return }
        let me = Unmanaged.passUnretained(self).toOpaque()   // the tray lives as long as the app
        Self.register(bus, Self.itemPath, Self.itemXML, "org.kde.StatusNotifierItem", me)
        Self.register(bus, Self.menuPath, Self.menuXML, "com.canonical.dbusmenu", me)
        _ = g_bus_own_name_on_connection(bus, busName, G_BUS_NAME_OWNER_FLAGS_NONE, nil, nil, nil, nil)
        // Register with the watcher now and whenever one appears (the panel started after Perch, or restarted).
        _ = g_bus_watch_name_on_connection(bus, "org.kde.StatusNotifierWatcher", G_BUS_NAME_WATCHER_FLAGS_NONE, { _, _, _, data in
            let tray = Unmanaged<Tray>.fromOpaque(data!).takeUnretainedValue()
            MainActor.assumeIsolated { tray.registerWithWatcher() }
        }, { _, _, _ in
            if ProcessInfo.processInfo.environment["PERCH_TRACE"] != nil { print("perch: no StatusNotifierWatcher, the tray icon waits for a panel") }
        }, me, nil)
    }

    /// The page's drawing of your character, as PNG data, for the icon.
    func setIcon(png: Data) {
        guard let images = Self.decode(png), !images.isEmpty else { return }
        pixmaps = images
        emit(Self.itemPath, "org.kde.StatusNotifierItem", "NewIcon", nil)
    }

    /// A new menu (an item came or went, a title changed).
    func setItems(_ items: [Item?]) {
        self.items = items
        revision += 1
        emit(Self.menuPath, "com.canonical.dbusmenu", "LayoutUpdated", GV.tuple([GV.u(revision), GV.i(0)]))
    }

    private func registerWithWatcher() {
        DBus.call(bus, "org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher", "org.kde.StatusNotifierWatcher", "RegisterStatusNotifierItem",
                  GV.tuple([GV.s(busName)])) { reply in
            if reply == nil { print("perch: the panel's StatusNotifierWatcher refused the tray icon") }
        }
    }

    private func emit(_ path: String, _ iface: String, _ name: String, _ args: OpaquePointer?) {
        guard let bus else { return }
        g_dbus_connection_emit_signal(bus, nil, path, iface, name, args, nil)
    }

    // MARK: the item

    private func property(_ iface: String, _ name: String) -> OpaquePointer? {
        if iface == "com.canonical.dbusmenu" {
            switch name {
            case "Version": return GV.u(3)
            case "TextDirection": return GV.s("ltr")
            case "Status": return GV.s("normal")
            case "IconThemePath": return GV.array("s", [])
            default: return nil
            }
        }
        switch name {
        case "Category": return GV.s("ApplicationStatus")
        case "Id": return GV.s("perch")
        case "Title": return GV.s("Perch")
        case "Status": return GV.s("Active")
        case "WindowId": return GV.i(0)
        case "IconThemePath", "IconName", "OverlayIconName", "AttentionIconName", "AttentionMovieName": return GV.s("")
        case "IconPixmap": return pixmapArray(pixmaps)
        case "OverlayIconPixmap", "AttentionIconPixmap": return pixmapArray([])
        case "ToolTip": return GV.tuple([GV.s(""), pixmapArray([]), GV.s("Perch"), GV.s("")])
        case "ItemIsMenu": return GV.b(true)   // a click opens the menu, as the Mac's menu-bar item does
        case "Menu": return GV.o(Self.menuPath)
        default: return nil
        }
    }

    private func pixmapArray(_ list: [(w: Int32, h: Int32, argb: [UInt8])]) -> OpaquePointer {
        GV.array("(iiay)", list.map { GV.tuple([GV.i($0.w), GV.i($0.h), GV.bytes($0.argb)]) })
    }

    /// Returns the reply tuple, or nil for no reply values.
    private func method(_ iface: String, _ name: String, _ args: OpaquePointer) -> OpaquePointer? {
        guard iface == "com.canonical.dbusmenu" else { return nil }   // Activate, ContextMenu, Scroll: the panel shows the menu itself
        switch name {
        case "GetLayout":
            let parent = GV.int(args, 0) ?? 0
            return GV.tuple([GV.u(revision), parent == 0 ? layout() : GV.tuple([GV.i(parent), props(parent), GV.array("v", [])])])
        case "GetGroupProperties":
            var ids: [Int32] = []
            if let list = GV.child(args, 0) {
                for i in 0..<Int(g_variant_n_children(list)) { if let c = GV.child(list, i) { ids.append(g_variant_get_int32(c)); g_variant_unref(c) } }
                g_variant_unref(list)
            }
            if ids.isEmpty { ids = [0] + items.indices.map { Int32($0 + 1) } }
            return GV.tuple([GV.array("(ia{sv})", ids.map { GV.tuple([GV.i($0), props($0)]) })])
        case "GetProperty":
            let id = GV.int(args, 0) ?? 0, key = GV.string(args, 1) ?? ""
            let all = props(id)
            let value = g_variant_lookup_value(all, key, nil) ?? GV.s("")
            g_variant_unref(g_variant_ref_sink(all))
            return GV.tuple([GV.v(value)])
        case "Event":
            if GV.string(args, 1) == "clicked", let id = GV.int(args, 0) { click(id) }
            return nil
        case "EventGroup":
            if let list = GV.child(args, 0) {
                for i in 0..<Int(g_variant_n_children(list)) {
                    guard let e = GV.child(list, i) else { continue }
                    if GV.string(e, 1) == "clicked", let id = GV.int(e, 0) { click(id) }
                    g_variant_unref(e)
                }
                g_variant_unref(list)
            }
            return GV.tuple([GV.array("i", [])])
        case "AboutToShow": return GV.tuple([GV.b(false)])
        case "AboutToShowGroup": return GV.tuple([GV.array("i", []), GV.array("i", [])])
        default: return nil
        }
    }

    /// Item ids are their place in the list plus one; 0 is the menu itself.
    private func props(_ id: Int32) -> OpaquePointer {
        if id == 0 { return GV.dict([("children-display", GV.s("submenu"))]) }
        let i = Int(id) - 1
        guard items.indices.contains(i), let item = items[i] else { return GV.dict([("type", GV.s("separator")), ("visible", GV.b(true))]) }
        return GV.dict([("label", GV.s(item.title.replacingOccurrences(of: "_", with: "__"))), ("enabled", GV.b(item.enabled)), ("visible", GV.b(true))])
    }

    private func layout() -> OpaquePointer {
        let children = items.indices.map { GV.v(GV.tuple([GV.i(Int32($0 + 1)), props(Int32($0 + 1)), GV.array("v", [])])) }
        return GV.tuple([GV.i(0), props(0), GV.array("v", children)])
    }

    private func click(_ id: Int32) {
        let i = Int(id) - 1
        guard items.indices.contains(i), let item = items[i], item.enabled else { return }
        DispatchQueue.main.async { item.action() }   // after the reply, so the panel closes its menu first
    }

    // MARK: GDBus plumbing

    private static func register(_ bus: OpaquePointer, _ path: String, _ xml: String, _ iface: String, _ me: UnsafeMutableRawPointer) {
        var err: UnsafeMutablePointer<GError>?
        guard let node = g_dbus_node_info_new_for_xml(xml, &err), let info = g_dbus_node_info_lookup_interface(node, iface) else {
            if let err { print("perch: tray interface: \(String(cString: err.pointee.message))"); g_error_free(err) }
            return
        }
        let vtable = UnsafeMutablePointer<GDBusInterfaceVTable>.allocate(capacity: 1)   // kept for the app's life
        vtable.initialize(to: GDBusInterfaceVTable())
        vtable.pointee.method_call = { _, _, _, iface, method, args, invocation, data in
            let tray = Unmanaged<Tray>.fromOpaque(data!).takeUnretainedValue()
            // Pointers cross the isolation boundary as integers (OpaquePointer is not Sendable).
            let reply = MainActor.assumeIsolated { tray.method(String(cString: iface!), String(cString: method!), args!).map { Int(bitPattern: $0) } }
            g_dbus_method_invocation_return_value(invocation, reply.flatMap { OpaquePointer(bitPattern: $0) })
        }
        vtable.pointee.get_property = { _, _, _, iface, name, _, data in
            let tray = Unmanaged<Tray>.fromOpaque(data!).takeUnretainedValue()
            let value = MainActor.assumeIsolated { tray.property(String(cString: iface!), String(cString: name!)).map { Int(bitPattern: $0) } }
            return value.flatMap { OpaquePointer(bitPattern: $0) }
        }
        g_dbus_connection_register_object(bus, path, info, vtable, me, nil, &err)
        if let err { print("perch: tray object \(path): \(String(cString: err.pointee.message))"); g_error_free(err) }
    }

    private static let itemXML = """
    <node><interface name="org.kde.StatusNotifierItem">
      <property name="Category" type="s" access="read"/><property name="Id" type="s" access="read"/>
      <property name="Title" type="s" access="read"/><property name="Status" type="s" access="read"/>
      <property name="WindowId" type="i" access="read"/><property name="IconThemePath" type="s" access="read"/>
      <property name="IconName" type="s" access="read"/><property name="IconPixmap" type="a(iiay)" access="read"/>
      <property name="OverlayIconName" type="s" access="read"/><property name="OverlayIconPixmap" type="a(iiay)" access="read"/>
      <property name="AttentionIconName" type="s" access="read"/><property name="AttentionIconPixmap" type="a(iiay)" access="read"/>
      <property name="AttentionMovieName" type="s" access="read"/><property name="ToolTip" type="(sa(iiay)ss)" access="read"/>
      <property name="ItemIsMenu" type="b" access="read"/><property name="Menu" type="o" access="read"/>
      <method name="ContextMenu"><arg name="x" type="i" direction="in"/><arg name="y" type="i" direction="in"/></method>
      <method name="Activate"><arg name="x" type="i" direction="in"/><arg name="y" type="i" direction="in"/></method>
      <method name="SecondaryActivate"><arg name="x" type="i" direction="in"/><arg name="y" type="i" direction="in"/></method>
      <method name="Scroll"><arg name="delta" type="i" direction="in"/><arg name="orientation" type="s" direction="in"/></method>
      <signal name="NewTitle"/><signal name="NewIcon"/><signal name="NewAttentionIcon"/><signal name="NewOverlayIcon"/><signal name="NewToolTip"/>
      <signal name="NewStatus"><arg name="status" type="s"/></signal>
    </interface></node>
    """

    private static let menuXML = """
    <node><interface name="com.canonical.dbusmenu">
      <property name="Version" type="u" access="read"/><property name="TextDirection" type="s" access="read"/>
      <property name="Status" type="s" access="read"/><property name="IconThemePath" type="as" access="read"/>
      <method name="GetLayout"><arg type="i" name="parentId" direction="in"/><arg type="i" name="recursionDepth" direction="in"/>
        <arg type="as" name="propertyNames" direction="in"/><arg type="u" name="revision" direction="out"/><arg type="(ia{sv}av)" name="layout" direction="out"/></method>
      <method name="GetGroupProperties"><arg type="ai" name="ids" direction="in"/><arg type="as" name="propertyNames" direction="in"/>
        <arg type="a(ia{sv})" name="properties" direction="out"/></method>
      <method name="GetProperty"><arg type="i" name="id" direction="in"/><arg type="s" name="name" direction="in"/><arg type="v" name="value" direction="out"/></method>
      <method name="Event"><arg type="i" name="id" direction="in"/><arg type="s" name="eventId" direction="in"/><arg type="v" name="data" direction="in"/>
        <arg type="u" name="timestamp" direction="in"/></method>
      <method name="EventGroup"><arg type="a(isvu)" name="events" direction="in"/><arg type="ai" name="idErrors" direction="out"/></method>
      <method name="AboutToShow"><arg type="i" name="id" direction="in"/><arg type="b" name="needUpdate" direction="out"/></method>
      <method name="AboutToShowGroup"><arg type="ai" name="ids" direction="in"/><arg type="ai" name="updatesNeeded" direction="out"/>
        <arg type="ai" name="idErrors" direction="out"/></method>
      <signal name="ItemsPropertiesUpdated"><arg type="a(ia{sv})" name="updatedProps"/><arg type="a(ias)" name="removedProps"/></signal>
      <signal name="LayoutUpdated"><arg type="u" name="revision"/><arg type="i" name="parent"/></signal>
      <signal name="ItemActivationRequested"><arg type="i" name="id"/><arg type="u" name="timestamp"/></signal>
    </interface></node>
    """

    // MARK: images

    /// A PNG at the sizes panels ask for (22 and 24 px, and twice that for HiDPI), as big-endian ARGB32.
    static func decode(_ png: Data) -> [(w: Int32, h: Int32, argb: [UInt8])]? {
        guard let loader = gdk_pixbuf_loader_new() else { return nil }
        defer { g_object_unref(loader) }
        let ok = png.withUnsafeBytes { buf in gdk_pixbuf_loader_write(loader, buf.baseAddress?.assumingMemoryBound(to: guchar.self), gsize(buf.count), nil) != 0 }
        guard gdk_pixbuf_loader_close(loader, nil) != 0, ok, let image = gdk_pixbuf_loader_get_pixbuf(loader) else { return nil }
        let w = Int(gdk_pixbuf_get_width(image)), h = Int(gdk_pixbuf_get_height(image))
        guard w > 0, h > 0 else { return nil }
        var out: [(w: Int32, h: Int32, argb: [UInt8])] = []
        for size in [22, 24, 44, 48] {
            let s = Double(size) / Double(max(w, h))
            let sw = max(1, Int((Double(w) * s).rounded())), sh = max(1, Int((Double(h) * s).rounded()))
            guard let scaled = gdk_pixbuf_scale_simple(image, Int32(sw), Int32(sh), GDK_INTERP_BILINEAR) else { continue }
            out.append((Int32(sw), Int32(sh), argb(scaled)))
            g_object_unref(UnsafeMutableRawPointer(scaled))
        }
        return out
    }

    private static func argb(_ p: OpaquePointer) -> [UInt8] {
        let w = Int(gdk_pixbuf_get_width(p)), h = Int(gdk_pixbuf_get_height(p)), stride = Int(gdk_pixbuf_get_rowstride(p))
        let n = Int(gdk_pixbuf_get_n_channels(p)), alpha = gdk_pixbuf_get_has_alpha(p) != 0
        guard let px = gdk_pixbuf_read_pixels(p) else { return [] }
        var out = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h { for x in 0..<w {
            let s = y * stride + x * n, d = (y * w + x) * 4
            out[d] = alpha ? px[s + 3] : 255; out[d + 1] = px[s]; out[d + 2] = px[s + 1]; out[d + 3] = px[s + 2]
        } }
        return out
    }

    /// Until the page draws your own character: the Mac's little dome with eyes, light grey for a dark panel.
    private static let dome: [(w: Int32, h: Int32, argb: [UInt8])] = [22, 44].map { size in
        var out = [UInt8](repeating: 0, count: size * size * 4)
        let k = 18.0 / Double(size)   // the drawing is on an 18-point grid, y down
        func inside(_ x: Double, _ y: Double) -> Bool {
            let body = x >= 3 && x <= 15 && y <= 15 && (y >= 9 || (x - 9) * (x - 9) + (y - 9) * (y - 9) <= 36)
            func eye(_ cx: Double) -> Bool { let dx = (x - cx) / 1.1, dy = (y - 9.8) / 1.8; return dx * dx + dy * dy <= 1 }
            return body && !eye(6.7) && !eye(11.3)
        }
        for py in 0..<size { for px in 0..<size {
            var hits = 0
            for sy in 0..<4 { for sx in 0..<4 { if inside((Double(px) + (Double(sx) + 0.5) / 4) * k, (Double(py) + (Double(sy) + 0.5) / 4) * k) { hits += 1 } } }
            let d = (py * size + px) * 4
            out[d] = UInt8(hits * 255 / 16); out[d + 1] = 0xe6; out[d + 2] = 0xe6; out[d + 3] = 0xe6
        } }
        return (Int32(size), Int32(size), out)
    }
}

/// Launch at login: ~/.config/autostart/perch.desktop (the XDG autostart folder every desktop reads), running this binary.
enum Autostart {
    private static var file: URL {
        let config = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory() + "/.config"
        return URL(fileURLWithPath: config).appendingPathComponent("autostart/perch.desktop")
    }

    /// The entry is there and not switched off (Hidden=true is how a desktop's settings turn one off).
    static var isOn: Bool {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return false }
        return !text.contains("Hidden=true") && !text.contains("X-GNOME-Autostart-enabled=false")
    }

    static func set(_ on: Bool) {
        guard on else { try? FileManager.default.removeItem(at: file); return }
        let text = """
        [Desktop Entry]
        Type=Application
        Name=Perch
        Comment=Where you left off with your coding agents
        Exec=\(quoted(executable))
        Terminal=false
        NoDisplay=true
        X-GNOME-Autostart-enabled=true

        """
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: file, atomically: true, encoding: .utf8)
        } catch { print("perch: launch at login failed: \(error)") }
    }

    /// Where this binary really is: the AppImage when run from one (its mount point changes every launch), else the
    /// running executable with links resolved.
    static var executable: String {
        if let image = ProcessInfo.processInfo.environment["APPIMAGE"], !image.isEmpty { return image }
        var buf = [CChar](repeating: 0, count: 4096)
        let n = readlink("/proc/self/exe", &buf, buf.count - 1)
        if n > 0 { buf[n] = 0; return String(cString: buf) }
        return URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().path
    }

    /// Exec's quoting: the path in double quotes, with ", `, $ and \ escaped for the quote and again for the string.
    static func quoted(_ path: String) -> String {
        var out = "\""
        for c in path {
            switch c {
            case "\"", "`", "$": out += "\\\\" + String(c)
            case "\\": out += "\\\\\\\\"
            case "%": out += "%%"
            default: out.append(c)
            }
        }
        return out + "\""
    }
}
