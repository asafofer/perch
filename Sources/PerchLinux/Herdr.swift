import Foundation

/// herdr, a multiplexer whose server outlives the terminal: its CLI focuses a pane, types into it and opens tabs.
/// The same commands as on the Mac; only where the CLI is installed differs.
enum Herdr {
    /// The CLI: the one the pane says it came with (HERDR_BIN_PATH), else the usual places.
    static func bin(_ hint: String?) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ([hint].compactMap { $0 } + [home + "/.local/bin/herdr", home + "/.cargo/bin/herdr", "/usr/local/bin/herdr", "/usr/bin/herdr", "/home/linuxbrew/.linuxbrew/bin/herdr"])
            .first { FileManager.default.isExecutableFile(atPath: $0) } ?? Proc.which("herdr") ?? "herdr"
    }
    /// Runs a command on that server. Some print JSON and some print nothing, so success is the exit status.
    @discardableResult
    private static func act(_ args: [String], socket: String, bin hint: String?) -> Bool {
        Terminals.tool(bin(hint), args, env: ["HERDR_SOCKET_PATH": socket]) != nil
    }
    /// Runs a command that answers in JSON, and reads the answer.
    private static func cli(_ args: [String], socket: String, bin hint: String?) -> [String: Any]? {
        guard let out = Terminals.tool(bin(hint), args, env: ["HERDR_SOCKET_PATH": socket]) else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [String: Any]
    }

    /// Shows the pane in every client attached to that server.
    @discardableResult
    static func focus(pane: String, socket: String, bin: String?) -> Bool {
        if act(["agent", "focus", pane], socket: socket, bin: bin) { return true }
        // Not an agent herdr recognises: show its tab.
        guard let r = cli(["pane", "get", pane], socket: socket, bin: bin)?["result"] as? [String: Any],
              let tab = (r["pane"] as? [String: Any])?["tab_id"] as? String else { return false }
        return act(["tab", "focus", tab], socket: socket, bin: bin)
    }

    /// The pane that has focus on that server, or nil when it cannot be read. With several clients attached it is only one
    /// of the places someone may be looking.
    static func focusedPane(socket: String, bin: String?) -> String? {
        ((cli(["api", "snapshot"], socket: socket, bin: bin)?["result"] as? [String: Any])?["snapshot"] as? [String: Any])?["focused_pane_id"] as? String
    }

    /// Types a line into the pane and presses Return: as a prompt to the agent there, else as raw text.
    static func type(_ line: String, pane: String, socket: String, bin: String?) -> Bool {
        if act(["agent", "prompt", pane, line], socket: socket, bin: bin) { return true }
        guard act(["pane", "send-text", pane, line], socket: socket, bin: bin) else { return false }
        return act(["pane", "send-keys", pane, "enter"], socket: socket, bin: bin)
    }

    /// The command that attaches to a server in a terminal.
    static func attach(session: String, bin: String?) -> String {
        let b = Terminals.shellQuote(Self.bin(bin))
        return session == "default" ? b : "\(b) --session \(Terminals.shellQuote(session))"
    }

    /// Whether a server answers on that socket.
    static func running(socket: String, bin: String?) -> Bool {
        FileManager.default.fileExists(atPath: socket) && act(["workspace", "list"], socket: socket, bin: bin)
    }

    /// A new tab in that workspace (or a new workspace if it is gone) that runs `command` in `cwd`, focused.
    @discardableResult
    static func run(_ command: String, cwd: String, workspace: String?, socket: String, bin: String?) -> Bool {
        var made = workspace.flatMap { cli(["tab", "create", "--workspace", $0, "--cwd", cwd, "--focus"], socket: socket, bin: bin) }
        if made == nil { made = cli(["workspace", "create", "--cwd", cwd, "--focus"], socket: socket, bin: bin) }
        guard let r = made?["result"] as? [String: Any], let pane = (r["root_pane"] as? [String: Any])?["pane_id"] as? String else { return false }
        return act(["pane", "run", pane, command], socket: socket, bin: bin)
    }

    /// Each agent herdr sees on that server, by pane: its state ("idle", "working", "blocked", "done", "unknown") and,
    /// when herdr's own integration reports it, the agent's session id.
    static func agents(socket: String, bin: String?) -> [String: (status: String, session: String?)] {
        guard let r = cli(["agent", "list"], socket: socket, bin: bin)?["result"] as? [String: Any], let list = r["agents"] as? [[String: Any]] else { return [:] }
        var out: [String: (String, String?)] = [:]
        for a in list {
            guard let pane = a["pane_id"] as? String else { continue }
            let s = a["agent_session"] as? [String: Any]
            out[pane] = (a["agent_status"] as? String ?? "unknown", s?["kind"] as? String == "id" ? s?["value"] as? String : nil)
        }
        return out
    }
}
