import Foundation
import PerchCore

/// tmux. Like herdr's, its server runs apart from any terminal (its panes' processes are the server's children); a client
/// in a terminal shows one of its sessions at a time. Each pane's processes carry $TMUX (the server's socket) and
/// $TMUX_PANE ("%3").
enum Tmux {
    struct Pane: Equatable {
        let socket: String
        /// "%3".
        let pane: String
        let session: String
        /// The tty of the client that shows (or can switch to) that session; nil when no terminal is attached.
        let client: String?
    }

    /// Runs tmux on that server.
    @discardableResult
    static func run(_ socket: String, _ args: [String]) -> String? { Terminals.tool("tmux", ["-S", socket] + args) }

    static func clients(_ socket: String) -> [TmuxList.Client] { TmuxList.clients(run(socket, ["list-clients", "-F", TmuxList.clientFormat]) ?? "") }
    static func panes(_ socket: String) -> [TmuxList.Pane] { TmuxList.panes(run(socket, ["list-panes", "-a", "-F", TmuxList.paneFormat]) ?? "") }

    /// Makes the pane its window's active one and that window its session's current one, so a client attached later shows it.
    @discardableResult
    static func select(_ p: Pane) -> Bool { run(p.socket, ["select-window", "-t", p.pane, ";", "select-pane", "-t", p.pane]) != nil }

    /// Shows the pane in the client that shows its session (switching that client to it if it shows another).
    /// False when no client is attached or the pane is gone.
    static func focus(_ p: Pane) -> Bool {
        guard select(p), let client = p.client else { return false }
        return run(p.socket, ["switch-client", "-c", client, "-t", p.pane]) != nil
    }

    /// The command that attaches a terminal to the pane's session.
    static func attach(_ p: Pane) -> String {
        "\(Terminals.shellQuote(Proc.which("tmux") ?? "tmux")) -S \(Terminals.shellQuote(p.socket)) attach-session -t \(Terminals.shellQuote(p.session))"
    }

    /// Types a line into the pane as one paste (bracketed when the program there asked for it, so a line break is not
    /// Return), then presses Return. A pane in copy mode leaves it first, or the keys would go to tmux.
    static func type(_ line: String, into p: Pane) -> Bool {
        if run(p.socket, ["display-message", "-p", "-t", p.pane, "#{pane_in_mode}"])?.hasPrefix("1") == true {
            run(p.socket, ["send-keys", "-t", p.pane, "-X", "cancel"])
        }
        let buffer = "perch-\(getpid())"
        guard run(p.socket, ["set-buffer", "-b", buffer, "--", line]) != nil,
              run(p.socket, ["paste-buffer", "-p", "-d", "-b", buffer, "-t", p.pane]) != nil else { return false }
        Thread.sleep(forTimeInterval: 0.05)
        return run(p.socket, ["send-keys", "-t", p.pane, "Enter"]) != nil
    }
}

/// kitty, through its remote control (`kitty @`). It answers only when kitty listens on a socket (`listen_on`, which its
/// processes see as $KITTY_LISTEN_ON) and allows remote control; otherwise Perch only raises its window.
enum Kitty {
    @discardableResult
    private static func ask(_ socket: String, _ args: [String], input: String? = nil) -> String? {
        Terminals.tool("kitty", ["@", "--to", socket] + args, input: input)
    }

    /// Shows that kitty window (its tab, in its OS window) and returns the X window that holds it.
    static func focus(window: String, socket: String) -> UInt? {
        guard ask(socket, ["focus-window", "--match", "id:\(window)"]) != nil, let id = Int(window),
              let ls = ask(socket, ["ls"]) else { return nil }
        return KittyList.platformWindow(of: id, in: Data(ls.utf8))
    }

    /// The process in the kitty window in front inside that X window.
    static func frontPid(socket: String, platformWindow: UInt) -> pid_t? {
        ask(socket, ["ls"]).flatMap { KittyList.frontPid(platformWindow: platformWindow, in: Data($0.utf8)) }
    }

    /// Types a line into that window and presses Return. The text goes in as it is, not read for escapes.
    static func type(_ line: String, window: String, socket: String) -> Bool {
        let text = line.contains(where: \.isNewline) ? TerminalLaunch.bracketed(line) : line
        guard ask(socket, ["send-text", "--match", "id:\(window)", "--stdin"], input: text) != nil else { return false }
        Thread.sleep(forTimeInterval: 0.05)
        return ask(socket, ["send-text", "--match", "id:\(window)", "--stdin"], input: "\r") != nil
    }
}

/// WezTerm, through `wezterm cli`, which finds the GUI's socket itself ($WEZTERM_UNIX_SOCKET when a pane says which).
enum Wezterm {
    @discardableResult
    private static func cli(_ args: [String], socket: String?, input: String? = nil) -> String? {
        Terminals.tool("wezterm", ["cli"] + args, env: socket.map { ["WEZTERM_UNIX_SOCKET": $0] } ?? [:], input: input)
    }

    /// Shows that pane in its tab and returns its title, which its window then carries.
    static func activate(pane: String, socket: String?) -> String? {
        guard cli(["activate-pane", "--pane-id", pane], socket: socket) != nil else { return nil }
        return cli(["list", "--format", "json"], socket: socket).flatMap { WeztermList.panes(Data($0.utf8)).first { String($0.id) == pane }?.title }
    }

    /// The tty of the pane the GUI has focused.
    static func focusedTty(socket: String?) -> String? {
        guard let id = cli(["list-clients", "--format", "json"], socket: socket).flatMap({ WeztermList.focusedPane(Data($0.utf8)) }) else { return nil }
        return cli(["list", "--format", "json"], socket: socket).flatMap { WeztermList.panes(Data($0.utf8)).first { $0.id == id }?.tty }
    }

    /// Types a line into the pane as a paste, then presses Return.
    static func type(_ line: String, pane: String, socket: String?) -> Bool {
        guard cli(["send-text", "--pane-id", pane, "--", line], socket: socket) != nil else { return false }
        Thread.sleep(forTimeInterval: 0.05)
        return cli(["send-text", "--pane-id", pane, "--no-paste", "--", "\r"], socket: socket) != nil
    }
}
