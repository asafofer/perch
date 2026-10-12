import Foundation
import Testing
@testable import PerchCore

@Suite struct LinuxTerminalsTests {
    @Test func statReadsANameWithSpacesAndParentheses() {
        let line = "4242 (my (odd) name) S 100 4242 100 34817 4242 4194304 90 0 0 0 0 0 0 0 20 0 1 0 44401806 8716288 480 18446744073709551615 0 0"
        let s = ProcStat.parse(line)
        #expect(s?.pid == 4242); #expect(s?.comm == "my (odd) name"); #expect(s?.ppid == 100)
        #expect(s?.pgrp == 4242); #expect(s?.ttyNr == 34817); #expect(s?.tpgid == 4242); #expect(s?.startTicks == 44401806)
        #expect(s?.tty == "/dev/pts/1"); #expect(s?.foreground == true)
        #expect(ProcStat.parse("garbage") == nil)
    }

    @Test func ttyNumbersBecomePaths() {
        #expect(ProcStat.ttyPath(0) == nil)
        #expect(ProcStat.ttyPath(136 << 8 | 7) == "/dev/pts/7")
        // Minor numbers past 255 keep their high bits above the major.
        #expect(ProcStat.ttyPath(Int32(136 << 8 | (300 & 0xff) | ((300 & 0xfff00) << 12))) == "/dev/pts/300")
        #expect(ProcStat.ttyPath(137 << 8 | 2) == "/dev/pts/258")
        #expect(ProcStat.ttyPath(4 << 8 | 2) == "/dev/tty2")
    }

    @Test func aProcessBehindAShellIsNotInFront() {
        let s = ProcStat.parse("10 (claude) S 9 10 9 34818 11 0 0 0 0 0 0 0 0 0 20 0 1 0 5 0 0")!
        #expect(!s.foreground)
    }

    @Test func procArgsAndEnvironment() {
        let cmd = Data("pi\0\0\0".utf8), env = Data("HOME=/h\0TMUX=/tmp/tmux-1000/default,77,0\0A=b=c\0junk\0HOME=/other\0".utf8)
        let a = ProcessArgs.parse(cmdline: cmd, environ: env, executable: "/usr/bin/node")
        #expect(a.argv == ["pi", "", ""]); #expect(a.environment["HOME"] == "/h"); #expect(a.environment["A"] == "b=c")
        #expect(Agent.recognise(executable: a.executable, argv0: a.argv.first) == .pi)
        #expect(TmuxList.socket(fromEnv: a.environment["TMUX"]) == "/tmp/tmux-1000/default")
        #expect(ProcessArgs.liveExecutable("/home/u/.local/share/claude/versions/2.1.0 (deleted)") == "/home/u/.local/share/claude/versions/2.1.0")
    }

    @Test func tmuxListsAndTheClientToShowAPaneIn() {
        let clients = TmuxList.clients("501\t/dev/pts/3\twork\t100\t%2\t/dev/pts/5\n502\t/dev/pts/4\tother\t300\t%7\t/dev/pts/9\n")
        #expect(clients.count == 2); #expect(clients[0].paneTty == "/dev/pts/5")
        #expect(TmuxList.client(for: "work", in: clients)?.pid == 501)
        #expect(TmuxList.client(for: "gone", in: clients)?.pid == 502)   // the one used last can switch to it
        #expect(TmuxList.client(for: "work", in: []) == nil)
        let panes = TmuxList.panes("%2\twork\t/dev/pts/5\t0\n%3\twork\t/dev/pts/6\t1\n")
        #expect(panes == [TmuxList.Pane(id: "%2", session: "work", tty: "/dev/pts/5", inMode: false), TmuxList.Pane(id: "%3", session: "work", tty: "/dev/pts/6", inMode: true)])
    }

    @Test func kittyListFindsTheXWindowAndWhatIsInFront() {
        let json = Data("""
        [{"id":1,"platform_window_id":111,"is_focused":false,"tabs":[{"id":1,"is_focused":true,"windows":[{"id":1,"is_focused":true,"pid":10}]}]},
         {"id":2,"platform_window_id":222,"is_focused":true,"tabs":[
            {"id":2,"is_focused":false,"windows":[{"id":2,"is_focused":false,"pid":20}]},
            {"id":3,"is_focused":true,"windows":[{"id":3,"is_focused":false,"pid":30},{"id":4,"is_focused":true,"pid":40}]}]}]
        """.utf8)
        #expect(KittyList.platformWindow(of: 2, in: json) == 222)
        #expect(KittyList.platformWindow(of: 9, in: json) == nil)
        #expect(KittyList.frontPid(platformWindow: 222, in: json) == 40)
        #expect(KittyList.frontPid(platformWindow: 111, in: json) == 10)
        #expect(KittyList.frontPid(platformWindow: nil, in: json) == 40)
    }

    @Test func weztermLists() {
        let panes = WeztermList.panes(Data(#"[{"window_id":0,"tab_id":0,"pane_id":3,"title":"claude","tty_name":"/dev/pts/4"}]"#.utf8))
        #expect(panes == [WeztermList.Pane(id: 3, title: "claude", tty: "/dev/pts/4")])
        let clients = Data(#"[{"focused_pane_id":3,"idle_time":{"secs":40,"nanos":0}},{"focused_pane_id":5,"idle_time":{"secs":2,"nanos":0}}]"#.utf8)
        #expect(WeztermList.focusedPane(clients) == 5)
    }

    @Test func theSystemsOwnTerminal() {
        #expect(TerminalLaunch.app(named: "/usr/bin/xfce4-terminal.wrapper") == "xfce4-terminal")
        #expect(TerminalLaunch.app(named: "/usr/bin/gnome-terminal.wrapper") == "gnome-terminal-server")
        #expect(TerminalLaunch.app(named: "/usr/bin/koi8rxterm") == "xterm")
        #expect(TerminalLaunch.app(named: "/usr/bin/kitty") == "kitty")
        #expect(TerminalLaunch.app(named: "/usr/bin/st") == nil)
        #expect(TerminalLaunch.fromHelpersRC("WebBrowser=firefox\nTerminalEmulator=gnome-terminal\n") == "gnome-terminal-server")
        #expect(TerminalLaunch.fromHelpersRC("WebBrowser=firefox\n") == nil)
    }

    @Test func openingAWindowKeepsTheShellAfterTheAgent() {
        let a = TerminalLaunch.argv(app: "xfce4-terminal", cwd: "/w/it's", command: "claude --resume abc", shell: "/bin/bash")!
        #expect(a.prefix(4) == ["xfce4-terminal", "--window", "--working-directory=/w/it's", "-x"])
        #expect(a.suffix(5) == ["/bin/bash", "-l", "-i", "-c", "cd '/w/it'\\''s' && claude --resume abc; exec '/bin/bash' -l"])
        #expect(TerminalLaunch.argv(app: "kitty", cwd: "/w", command: "x", shell: "/bin/zsh")?.prefix(3) == ["kitty", "--directory", "/w"])
        #expect(TerminalLaunch.argv(app: "tilix", cwd: "/w", command: "x", shell: "/bin/sh")?.count == 4)
        #expect(TerminalLaunch.argv(app: "code", cwd: "/w", command: "x", shell: "/bin/sh") == nil)
        for app in TerminalLaunch.binaries.keys { #expect(TerminalLaunch.argv(app: app, cwd: "/w", command: "x", shell: "/bin/sh") != nil) }
    }

    @Test func bracketedPasteCannotBeEndedEarly() {
        #expect(TerminalLaunch.bracketed("a\nb\u{1b}[201~c") == "\u{1b}[200~a\nbc\u{1b}[201~")
    }

    @Test func theWindowTitledWithTheSessionWins() {
        let titles = ["u@h: ~", "u@h: ~/code/perch", "\u{2733} Fix the login bug", "u@h: ~/code/perch"]
        #expect(WindowPick.best(titles, cwd: "/home/u/code/perch", home: "/home/u", hints: ["Fix the login bug"]) == 2)
        // Two windows in the same folder: the one nearer the top.
        #expect(WindowPick.best(titles, cwd: "/home/u/code/perch", home: "/home/u", hints: []) == 3)
        #expect(WindowPick.best(titles, cwd: "/srv/other", home: "/home/u", hints: []) == nil)
        #expect(WindowPick.best(["u@h: ~"], cwd: "/home/u", home: "/home/u", hints: []) == 0)
    }
}
