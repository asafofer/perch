import CPerchLinux
import Foundation

/// D-Bus through GIO's GDBus, on GLib's loop: replies and signals arrive on the main thread. Swift sees none of GLib's
/// variadic GVariant constructors, so values are built with `GV` from the typed ones.
enum DBus {
    @MainActor static let session: OpaquePointer? = connect(G_BUS_TYPE_SESSION)
    @MainActor static let system: OpaquePointer? = connect(G_BUS_TYPE_SYSTEM)

    private static func connect(_ type: GBusType) -> OpaquePointer? {
        var err: UnsafeMutablePointer<GError>?
        let c = g_bus_get_sync(type, nil, &err)
        if let err { if ProcessInfo.processInfo.environment["PERCH_TRACE"] != nil { print("perch: no D-Bus \(type == G_BUS_TYPE_SYSTEM ? "system" : "session") bus: \(String(cString: err.pointee.message))") }; g_error_free(err) }
        return c
    }

    /// Calls a method without starting a service that is not running. `done` gets the reply tuple, or nil on any error
    /// (no such service, no such object, a timeout). The reply is only valid inside `done`.
    @MainActor
    static func call(_ bus: OpaquePointer?, _ dest: String, _ path: String, _ iface: String, _ method: String, _ args: OpaquePointer? = nil,
                     timeout: Int32 = 1000, done: @escaping @MainActor (OpaquePointer?) -> Void) {
        guard let bus else { done(nil); return }
        let box = Unmanaged.passRetained(Reply(done)).toOpaque()
        g_dbus_connection_call(bus, dest, path, iface, method, args, nil, G_DBUS_CALL_FLAGS_NO_AUTO_START, timeout, nil, { source, result, data in
            let reply = Unmanaged<Reply>.fromOpaque(data!).takeRetainedValue()
            var err: UnsafeMutablePointer<GError>?
            let v = g_dbus_connection_call_finish(OpaquePointer(source), result, &err)
            if let err { g_error_free(err) }
            MainActor.assumeIsolated { reply.done(v) }
            if let v { g_variant_unref(v) }
        }, box)
    }

    /// A property's value, unwrapped from its variant, through org.freedesktop.DBus.Properties.Get.
    @MainActor
    static func property(_ bus: OpaquePointer?, _ dest: String, _ path: String, _ iface: String, _ name: String, done: @escaping @MainActor (OpaquePointer?) -> Void) {
        call(bus, dest, path, "org.freedesktop.DBus.Properties", "Get", GV.tuple([GV.s(iface), GV.s(name)])) { reply in
            guard let reply, let boxed = GV.child(reply, 0) else { done(nil); return }
            let inner = g_variant_get_variant(boxed)
            done(inner)
            g_variant_unref(inner); g_variant_unref(boxed)
        }
    }

    /// Calls `handler` with each matching signal's arguments (a tuple). Returns the subscription id.
    @MainActor @discardableResult
    static func subscribe(_ bus: OpaquePointer?, sender: String?, iface: String, member: String, path: String?,
                          _ handler: @escaping @MainActor (OpaquePointer) -> Void) -> UInt32 {
        guard let bus else { return 0 }
        let box = Unmanaged.passRetained(Signal(handler)).toOpaque()
        return g_dbus_connection_signal_subscribe(bus, sender, iface, member, path, nil, G_DBUS_SIGNAL_FLAGS_NONE, { _, _, _, _, _, params, data in
            let s = Unmanaged<Signal>.fromOpaque(data!).takeUnretainedValue()
            if let params { MainActor.assumeIsolated { s.handler(params) } }
        }, box, { data in Unmanaged<Signal>.fromOpaque(data!).release() })
    }

    private final class Reply { let done: @MainActor (OpaquePointer?) -> Void; init(_ d: @escaping @MainActor (OpaquePointer?) -> Void) { done = d } }
    private final class Signal { let handler: @MainActor (OpaquePointer) -> Void; init(_ h: @escaping @MainActor (OpaquePointer) -> Void) { handler = h } }
}

/// GVariant values, built and read. New values are floating: a container or a D-Bus call takes them over.
enum GV {
    static func s(_ v: String) -> OpaquePointer { g_variant_new_string(v) }
    static func o(_ v: String) -> OpaquePointer { g_variant_new_object_path(v) }
    static func i(_ v: Int32) -> OpaquePointer { g_variant_new_int32(v) }
    static func u(_ v: UInt32) -> OpaquePointer { g_variant_new_uint32(v) }
    static func b(_ v: Bool) -> OpaquePointer { g_variant_new_boolean(v ? 1 : 0) }
    static func v(_ x: OpaquePointer) -> OpaquePointer { g_variant_new_variant(x) }
    static func tuple(_ items: [OpaquePointer]) -> OpaquePointer {
        let p: [OpaquePointer?] = items
        return p.withUnsafeBufferPointer { g_variant_new_tuple($0.baseAddress, gsize(items.count)) }
    }
    /// An array of `element` (a type string such as "{sv}"); an empty one needs the type.
    static func array(_ element: String, _ items: [OpaquePointer]) -> OpaquePointer {
        let t = g_variant_type_new(element)
        defer { g_variant_type_free(t) }
        let p: [OpaquePointer?] = items
        return p.withUnsafeBufferPointer { g_variant_new_array(t, $0.baseAddress, gsize(items.count)) }
    }
    /// a{sv}
    static func dict(_ pairs: [(String, OpaquePointer)]) -> OpaquePointer { array("{sv}", pairs.map { g_variant_new_dict_entry(s($0.0), v($0.1)) }) }
    /// ay
    static func bytes(_ data: [UInt8]) -> OpaquePointer {
        let t = g_variant_type_new("y")
        defer { g_variant_type_free(t) }
        return data.withUnsafeBufferPointer { g_variant_new_fixed_array(t, $0.baseAddress, gsize(data.count), 1) }
    }

    /// A child of a container, or nil when there is no such child. The caller unrefs it.
    static func child(_ v: OpaquePointer, _ i: Int) -> OpaquePointer? { i < Int(g_variant_n_children(v)) ? g_variant_get_child_value(v, gsize(i)) : nil }
    static func bool(_ v: OpaquePointer, _ i: Int) -> Bool? {
        guard let c = child(v, i) else { return nil }
        defer { g_variant_unref(c) }
        let t = String(cString: g_variant_get_type_string(c))
        if t == "b" { return g_variant_get_boolean(c) != 0 }
        if t == "v", let inner = g_variant_get_variant(c) {
            defer { g_variant_unref(inner) }
            return String(cString: g_variant_get_type_string(inner)) == "b" ? g_variant_get_boolean(inner) != 0 : nil
        }
        return nil
    }
    static func int(_ v: OpaquePointer, _ i: Int) -> Int32? {
        guard let c = child(v, i) else { return nil }
        defer { g_variant_unref(c) }
        return String(cString: g_variant_get_type_string(c)) == "i" ? g_variant_get_int32(c) : nil
    }
    static func string(_ v: OpaquePointer, _ i: Int) -> String? {
        guard let c = child(v, i) else { return nil }
        defer { g_variant_unref(c) }
        let t = String(cString: g_variant_get_type_string(c))
        return ["s", "o"].contains(t) ? String(cString: g_variant_get_string(c, nil)) : nil
    }
}
