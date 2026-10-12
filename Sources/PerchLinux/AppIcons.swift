import CPerchLinux
import Foundation
import PerchCore

/// The real icons of the apps the page talks about, from the icon theme, as data URLs keyed like the Mac's: "terminal"
/// (the terminal you use), each terminal by the name the page knows it by (Terminals.keys), and "opencode" when its
/// desktop app is installed. An app is found by its .desktop entry, whose Icon= the theme resolves to a file.
enum AppIcons {
    /// Each key and the .desktop files that app installs as, most likely first. One not listed is found by the window
    /// class it names (StartupWMClass) or by its file name.
    private static let desktopFiles: [String: [String]] = [
        "xfce4-terminal": ["xfce4-terminal.desktop"],
        "gnome-terminal": ["org.gnome.Terminal.desktop", "gnome-terminal.desktop"],
        "kitty": ["kitty.desktop"],
        "alacritty": ["Alacritty.desktop", "alacritty.desktop", "org.alacritty.Alacritty.desktop"],
        "wezterm": ["org.wezfurlong.wezterm.desktop", "wezterm.desktop"],
        "ghostty": ["com.mitchellh.ghostty.desktop", "ghostty.desktop"],
        "konsole": ["org.kde.konsole.desktop", "konsole.desktop"],
        "xterm": ["debian-xterm.desktop", "xterm.desktop"],
        "tilix": ["com.gexperts.Tilix.desktop", "tilix.desktop"],
        "terminator": ["terminator.desktop"],
        "vscode": ["code.desktop", "code-oss.desktop", "visual-studio-code.desktop", "com.visualstudio.code.desktop", "codium.desktop"],
        "cursor": ["cursor.desktop", "Cursor.desktop", "co.anysphere.cursor.desktop"],
        "zed": ["dev.zed.Zed.desktop", "zed.desktop"],
        // The OpenCode desktop app, when it is installed. pi has no app: the page draws its own mark.
        "opencode": ["opencode-desktop.desktop", "ai.opencode.desktop.desktop", "OpenCode.desktop", "opencode.desktop"],
    ]

    /// Every key the page could get a real icon for (pi, Claude and Codex have no app here).
    private static var keys: Set<String> { Set(desktopFiles.keys).union(Terminals.keys.values).union(["terminal"]) }

    /// Whether the page could get a real icon for this key at all.
    static func knows(_ key: String) -> Bool { keys.contains(key) }

    /// Encoded icons by file, read again only when the file changes.
    nonisolated(unsafe) private static var cache: [String: (mtime: Date, url: String)] = [:]

    /// Main thread: GTK's icon theme is. Called from elsewhere, it waits for the main thread.
    static func all() -> [String: String] {
        guard Thread.isMainThread else { return DispatchQueue.main.sync { all() } }
        let entries = DesktopEntry.all()
        var out: [String: String] = [:]
        for key in keys where key != "terminal" {
            if let icon = entry(for: key, in: entries)?.icon, let data = dataURL(icon) { out[key] = data }
        }
        // The terminal you use: its own icon, else any terminal's, else the theme's own terminal icon.
        let preferred = Terminals.keys[Terminals.preferred] ?? Terminals.preferred
        let terminals = Set(desktopFiles.keys).union(Terminals.keys.values).subtracting(["opencode"]).sorted()
        out["terminal"] = out[preferred] ?? terminals.lazy.compactMap { out[$0] }.first ?? dataURL("utilities-terminal")
        return out
    }

    /// The app's .desktop entry: by its known file names, then by the window class it names, then by its own file name.
    private static func entry(for key: String, in entries: [DesktopEntry]) -> DesktopEntry? {
        for name in desktopFiles[key] ?? [] { if let e = entries.first(where: { $0.file == name }) { return e } }
        let classes = Set([key] + Terminals.keys.filter { $0.value == key }.map(\.key))
        if let e = entries.first(where: { $0.wmClass.map { classes.contains($0.lowercased()) } ?? false }) { return e }
        return entries.first { e in
            let stem = (e.file as NSString).deletingPathExtension.lowercased()
            return classes.contains(stem) || classes.contains { stem.hasSuffix("." + $0) }
        }
    }

    /// An Icon= value as a data URL at 64 px: an SVG as it is, anything else drawn at that size as a PNG.
    private static func dataURL(_ icon: String) -> String? {
        guard let path = file(for: icon), let mtime = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date else { return nil }
        if let hit = cache[path], hit.mtime == mtime { return hit.url }
        var url: String?
        if path.lowercased().hasSuffix(".svg") {
            url = (try? Data(contentsOf: URL(fileURLWithPath: path))).map { "data:image/svg+xml;base64," + $0.base64EncodedString() }
        } else {
            url = png(path, size: 64).map { "data:image/png;base64," + $0.base64EncodedString() }
        }
        if let url { cache[path] = (mtime, url) }
        return url
    }

    /// Where an Icon= value lives: a path as given, else what the icon theme has for that name at 64 px, else
    /// /usr/share/pixmaps (xterm's "mini.xterm" is mini.xterm_48x48.xpm there).
    private static func file(for icon: String) -> String? {
        let fm = FileManager.default
        if icon.hasPrefix("/") { return fm.fileExists(atPath: icon) ? icon : nil }
        // An Icon= with an extension is a file name; the theme looks names up without it.
        let ext = (icon as NSString).pathExtension.lowercased()
        let name = ["png", "svg", "xpm"].contains(ext) ? (icon as NSString).deletingPathExtension : icon
        if let display = gdk_display_get_default(), let theme = gtk_icon_theme_get_for_display(display), gtk_icon_theme_has_icon(theme, name) != 0,
           let found = gtk_icon_theme_lookup_icon(theme, name, nil, 64, 1, GTK_TEXT_DIR_NONE, GtkIconLookupFlags(rawValue: 0)) {
            defer { g_object_unref(raw(found)) }
            if let f = gtk_icon_paintable_get_file(found) {
                defer { g_object_unref(raw(f)) }
                if let path = takeGString(g_file_get_path(f)), fm.fileExists(atPath: path) { return path }
            }
        }
        let pixmaps = "/usr/share/pixmaps"
        let files = ((try? fm.contentsOfDirectory(atPath: pixmaps)) ?? []).filter { $0.hasPrefix(name + ".") || $0.hasPrefix(name + "_") }
        // An SVG, else the largest picture ("_48x48" over "_32x32").
        func size(_ f: String) -> Int { f.hasSuffix(".svg") ? .max : Int(f.split(separator: "_").last?.split(separator: "x").first ?? "") ?? 1 }
        return files.max { size($0) < size($1) }.map { pixmaps + "/" + $0 }
    }

    /// A picture file drawn at `size` px, as PNG data. gdk-pixbuf reads PNG, XPM, SVG and the rest.
    private static func png(_ path: String, size: Int32) -> Data? {
        var error: UnsafeMutablePointer<GError>?
        guard let pixbuf = gdk_pixbuf_new_from_file_at_size(path, size, size, &error) else { if let error { g_error_free(error) }; return nil }
        defer { g_object_unref(raw(pixbuf)) }
        var buffer: UnsafeMutablePointer<gchar>?
        var length: gsize = 0
        guard gdk_pixbuf_save_to_bufferv(pixbuf, &buffer, &length, "png", nil, nil, &error) != 0, let buffer else { if let error { g_error_free(error) }; return nil }
        defer { g_free(buffer) }
        return Data(bytes: buffer, count: Int(length))
    }
}

/// An app's .desktop entry, the part that says how it shows: its icon and the window class its windows carry.
struct DesktopEntry {
    /// The file's name, its desktop id ("kitty.desktop").
    let file: String
    let icon: String?
    let wmClass: String?

    /// The application folders, the user's first (XDG_DATA_HOME, then XDG_DATA_DIRS, then Flatpak's and Snap's exports).
    static var folders: [String] {
        let env = ProcessInfo.processInfo.environment, home = FileManager.default.homeDirectoryForCurrentUser.path
        let user = env["XDG_DATA_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? home + "/.local/share"
        let system = (env["XDG_DATA_DIRS"].flatMap { $0.isEmpty ? nil : $0 } ?? "/usr/local/share:/usr/share").split(separator: ":").map(String.init)
        let extra = [home + "/.local/share/flatpak/exports/share", "/var/lib/flatpak/exports/share", "/var/lib/snapd/desktop"]
        var seen = Set<String>()
        return ([user] + system + extra).map { $0 + "/applications" }.filter { seen.insert($0).inserted }
    }

    /// Every entry, one per desktop id: the user's copy hides the system's, as the menus do.
    static func all() -> [DesktopEntry] {
        let fm = FileManager.default
        var out: [DesktopEntry] = [], ids = Set<String>()
        for dir in folders {
            // Entries can sit one folder down ("kde4/konsole.desktop").
            var files = (try? fm.contentsOfDirectory(atPath: dir)) ?? []
            for sub in files where !sub.hasSuffix(".desktop") {
                files += ((try? fm.contentsOfDirectory(atPath: dir + "/" + sub)) ?? []).map { sub + "/" + $0 }
            }
            for f in files where f.hasSuffix(".desktop") {
                let id = f.replacingOccurrences(of: "/", with: "-")
                guard ids.insert(id).inserted, let e = parse(dir + "/" + f, id: id) else { continue }
                out.append(e)
            }
        }
        return out
    }

    /// Reads the [Desktop Entry] group. A hidden entry (Hidden=true) is a deleted one.
    static func parse(_ path: String, id: String) -> DesktopEntry? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        var inMain = false, values: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let l = line.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("[") { inMain = l == "[Desktop Entry]"; continue }
            guard inMain, let eq = l.firstIndex(of: "=") else { continue }
            let key = l[..<eq].trimmingCharacters(in: .whitespaces)
            if values[key] == nil { values[key] = l[l.index(after: eq)...].trimmingCharacters(in: .whitespaces) }
        }
        guard values["Hidden"] != "true" else { return nil }
        return DesktopEntry(file: id, icon: values["Icon"].flatMap { $0.isEmpty ? nil : $0 }, wmClass: values["StartupWMClass"])
    }
}

/// Whether an agent is on this machine: the folder it keeps sessions in, or its command where installers put it.
enum AgentPresence {
    static func installed(_ a: Agent) -> Bool {
        let home = SessionHome.path, fm = FileManager.default
        let folders: [String: [String]] = [
            "claude": [home + "/.claude"], "codex": [home + "/.codex"],
            "opencode": [home + "/.local/share/opencode/opencode.db"], "pi": [home + "/.pi/agent"],
        ]
        if (folders[a.id] ?? []).contains(where: fm.fileExists(atPath:)) { return true }
        return binFolders.contains { fm.isExecutableFile(atPath: $0 + "/" + a.id) }
    }

    /// PATH, then where installers put commands when Perch was started without them on its PATH (from a desktop menu):
    /// the user's own bins, bun's, npm's global prefix, every node version nvm has, and the system's.
    static var binFolders: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let nvm = ((try? FileManager.default.contentsOfDirectory(atPath: home + "/.nvm/versions/node")) ?? []).map { home + "/.nvm/versions/node/\($0)/bin" }
        return path + [home + "/.local/bin", home + "/bin", home + "/.bun/bin", home + "/.npm-global/bin", home + "/.opencode/bin"] + nvm + ["/usr/local/bin", "/usr/bin"]
    }
}
