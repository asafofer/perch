# Perch: guide for people and agents picking this up

Perch is a macOS notch app. When a developer comes back to their Mac, it tells them where they left off across their coding agents (Claude Code, Codex, OpenCode, pi) and lets them jump back in, reply, snooze, or change settings, all from the notch. It is a portfolio-quality project: the bar is delight, polish and restraint, not feature count. Four jobs, in order: where was I, jump back in, what needs me, answer from the notch. Sessions from the Claude app (Code), the Codex app, and Claude Code, Codex, OpenCode or pi in any terminal, including inside the herdr and cmux multiplexers.

Read this file first. `README.md` has install and usage. How each feature behaves is in `docs/behavior/`, one file per area (see [Behaviour docs](#behaviour-docs)).

## How the work is done here

1. **Show it in the design page first.** New UI or a visible change goes into `ui/design.html` (the real UI with sample data) and gets looked at before it is built into the app. Whenever you build or change a design there, open the design page for the owner yourself (the browser pane, on the scenario that shows it) and give its link, `/design.html?c=<category>&s=<scenario>` (names or slugs; picking a scenario puts its link in the address bar); do not only describe it or draw a mock-up in chat. Serve it from this checkout's own `ui/` with `preview_start` "design" and open `/design.html`: `scripts/worktree-setup.sh` (run when a session starts) gives each checkout its own port in `.claude/launch.json`, so it never shows another worktree's old files. It also installs `ui/node_modules` and copies `ui/icons.local.json` from the main checkout. The owner will say "build it" when approved. Small fixes and bugs can go straight in.
2. **Look at it before you say it is done.** Check each state in the design page, and say plainly what you checked and what you did not. Mock-ups sit on Raycast wallpapers (`ui/wallpapers/`, from raycast.com/wallpapers). A change to how Perch talks to another app (a new terminal, multiplexer or agent especially) is also run in the real app with that tool installed; a stand-in or `swift test` alone does not count, and the PR says what was driven and what was not.
3. **Commits:** one-line messages, no mention of AI or co-authors. Commit after every working step.
4. **Tests must stay green:** `swift test`. CI runs it on every PR, with the UI checks (`ui/app.js` ASCII only and parsing, `ui/dist/ui.css` matching a fresh build) and the PR description check; all three must pass to merge into `main`, which takes changes only through a pull request. Outside contributors start from CONTRIBUTING.md.
5. **Opening a PR:** agents use the `open-pr` skill (`.claude/skills/open-pr`). The body follows `.github/pull_request_template.md` and carries a demo filmed from the design page (`./scripts/pr-demo.sh --publish`; the media lives on the `pr-media` branch, never main). A hook (`.claude/hooks/pr-body-check.py`) refuses `gh pr create` without the template. No visible change: Demo says so.
6. **Keep the docs true.** A change in behaviour updates its file in `docs/behavior/` in the same PR; a new area gets its own file and a line under Behaviour docs. This file holds only what every task needs: the workflow, the map, the rules and the traps.

## Architecture

```
Sources/PerchCore   Pure logic, no UI, fully tested.
  NotchMachine        State machine: idle, open, switcher, restoring, onboarding, settings.
  NotchGeometry       Panel and tab sizes, hover rects. Takes ScreenInfo so it is testable. ScreenPicker: which display the cursor is on.
  Agent               Each agent's names, resume command, whether Perch answers it from the notch, how to spot its process.
  Project, Transcript Session model, JSONL parsing (Claude Code and Codex), recap text, git parsing.
  OpenCode, Pi        OpenCode's SQLite database (read-only, OpenCode 1's tables and 2's) and pi's session files, into the same SessionDigest.
  Conductor           ConductorSessions: Conductor's SQLite database (read-only) maps a Claude Code session id or Codex thread id to its workspace.
  LiveStatus          Hook events (HookEvent), what an agent asks (Ask: words for the card, the reply JSON), live status per session.
  SessionScan         SessionScanner: which sessions get a row (Claude app list, Codex threads, OpenCode, pi), tail reading, caches.
  Focus               Which running session you are in: a Spot (cmux surface, herdr pane, tty) compared with what is in front (Looking).
  Shortcut            The shortcut that opens Perch, its rules, ModifierTap and ShortcutRecorder.
  ScreenTarget        Which screen Perch opens on (ShowOn: the mouse's, the active window's, or a display by its UUID), with fallbacks to the mouse; window-list rects to Cocoa's.
  NewSession          Starting a session from the notch: the agents on this Mac (Choice), the folders to offer, what it starts on, a terminal agent's command, and which scanned session is the new one (started).
  PullRequests        A session's pull requests: the Claude app's list, what the GitHub CLI says (GitHubCLI, parse), the cache that asks it (PullRequestChecker), and what a session shows.
  Feedback            What Send feedback sends: the 4 MB limit for files, the email check, the subject, the multipart form.
  InstalledCopy       A test build's way back (its menu's Back to installed Perch): which other copy is the installed one.
  Place               Where a running agent lives (herdr pane, tmux pane, cmux surface, tab) from its environment; what a tmux server says (TmuxServer); which process is which session (Running); herdr's status (HerdrStatus).
Sources/Perch       The AppKit shell.
  main.swift          Launch flags, hotkeys, status item menu, first-run onboarding.
  NotchController     Owns the machine, the panel, the WKWebView, timers, hover, keys, refresh.
  RealSessionProvider Runs the SessionScanner, keeps per-app counts and what each card was built from.
  HookServer          Unix socket (~/.config/perch/perch.sock) the hooks post to; holds a request open until you answer. HookInstaller writes the hook entries,
                      and for OpenCode and pi Perch's own plugin file (PerchPlugins).
  FocusProbe          Reads what is in front, a second apart off the main thread, for Focus.
  Terminals           Running agents from the process table (LiveSessions), going back to them (tab, herdr or tmux pane, cmux surface), typing into them.
  ClaudeComposer      A reply into a Claude app session through Accessibility, Claude's window left behind.
  NewSessionStarter   Starts a new session: the Claude or Codex app's own link with your words, then Send through Accessibility; or a terminal window running the agent.
  FeedbackSender      Send feedback: posts it to the feedback function (pictures made smaller first), or opens Mail with it.
  PullRequestState    Which mode applies (Off, Marks, Checks), whether the CLI works, and the checker the list is decorated by.
  Snapshot            The JSON Swift sends to the page. The page never decides anything.
  Preferences         UserDefaults: onboarded, character, enabled apps, idle minutes.
  HotkeyService       Carbon hotkeys and the Command+Option tap (needs Accessibility).
ui/                 The interface, plain JS and Tailwind v3 (shadcn-style classes), Inter bundled.
  app.js              All rendering. window.perch.apply(snapshot) draws; messages go back through
                      webkit.messageHandlers.perch. A browser-only dev harness (window.perchDev) runs it with sample data.
  input.css           Tailwind plus the notch, glow and character styles.
  orbs.js             Thinking Orbs (thinkingorbs.com, MIT), vendored as a plain script: the orb beside a working step.
  design.html         The design page. Scenarios for every state; the Motion category plays each small motion.
  motion.html         Before and after of each motion taken from transitions.dev, the page they were approved on.
feedback/           The Vercel function Send feedback posts to; it emails the message through Resend (feedback/README.md).
```

Data flow: Swift decides state (`NotchMachine`), builds a `UISnapshot`, calls `window.perch.apply(json)`. The page draws and posts events (`confirm`, `snooze`, `reply`, `settings`, `onb`, `character`, `source`, `setting`, ...). Handle new events in `NotchController.userContentController`.

## Behaviour docs

Before changing an area, read its file in `docs/behavior/`:

- [sessions.md](docs/behavior/sessions.md): the list, where Claude and Codex sessions come from, Pick up and going back to a terminal.
- [card.md](docs/behavior/card.md): the card's words (outcome, Next, the Now row), selecting and copying.
- [replies.md](docs/behavior/replies.md): the reply view, drafts, attached files and pasted pictures, sending into Claude or a terminal.
- [new-session.md](docs/behavior/new-session.md): starting a session from the notch.
- [agents.md](docs/behavior/agents.md): OpenCode, pi, Conductor, herdr, tmux, cmux, and which process is which session.
- [status.md](docs/behavior/status.md): hooks against the transcript, answering permissions and questions, background work, testing the hook socket.
- [speaking-up.md](docs/behavior/speaking-up.md): the session you are in, the live activity, Sent, the welcome card.
- [keyboard.md](docs/behavior/keyboard.md): the shortcut that opens Perch, and when a card takes the keyboard.
- [displays.md](docs/behavior/displays.md): which screen Perch shows on, hover, displays without a notch.
- [settings.md](docs/behavior/settings.md): the Settings list and its pages, their keys, Send feedback and where it goes.
- [pull-requests.md](docs/behavior/pull-requests.md): the pull request mark and its label, where they come from (the Claude app, or GitHub through the GitHub CLI), and what needs you.
- [updates.md](docs/behavior/updates.md): Sparkle, signing, What's new, update errors, Accessibility lost after an update.

## Running and building

```bash
cd ui && npm install && cd ..       # once
./scripts/make-dev-cert.sh          # once: stable signing identity so macOS keeps permissions
./scripts/run.sh --show             # build and launch, show the card
./scripts/run.sh --idle 15          # welcome card after 15 s idle (testing). Relaunch without it afterwards.
swift test
./scripts/package.sh                # build/Perch.zip for sharing
./scripts/make-dmg.sh               # build/Perch.dmg: the window people drag Perch to Applications in (a release carries it beside the zip Sparkle updates from)
node scripts/render-dmg-background.mjs  # Resources/dmg/background.png and @2x from ui/install/background.html (the design page's Installing tab shows it)
./scripts/make-icon.sh              # Resources/AppIcon.icns and docs/assets/icon.png from docs/assets/icon.svg (WebKit draws the coat)
./scripts/record.sh                 # the README's GIF, filmed from design.html?record (needs ffmpeg; headless, about 22 s)
./scripts/pr-demo.sh [scenario...] [--publish]   # a PR's demo from the design page (see Opening a PR)
./scripts/agents-demo.sh [folder]   # herdr with pi, OpenCode, Claude Code and Codex side by side, and pi alone, in cmux
```

Useful flags: `--show`, `--simulate`, `--onboarding` (replays it from the hello), `--hello` (the hello beside the notch after setup), `--demo`, `--idle <s>`, `--snapshot <dir>`, `--dump` (prints what the scan finds), `PERCH_TRACE=1` for state logging.

## Design rules (the owner is firm about these)

- Linear-grade restraint. Neutral sans (Inter), tight tracking, sentence case, small type (card text 13 to 14 px), small call-to-action buttons.
- **No dividing lines.** No pulsing or glowing dots (the list's status rings and the pull request mark have a faint, still glow; nothing else). No drawn icons where a real app icon exists (use the real Claude, Codex and OpenCode icons from `AppIcons`). pi has no app, so the page draws pi.dev's own mark; OpenCode's opencode.ai mark stands in when its app is not installed.
- The character is a soft plush shape with flat, matte eyes. Its depth is one SVG filter on the body (`coatFilter` in `app.js`): light from the top left, a rounded form, shade that deepens its colour, a rim of light, and from 30 px up a fuzzy edge and faint grain. Small, it keeps a crisp outline. Nothing else goes on the character. Shapes live in `SHAPES` in `app.js`.
- Glow is internal, soft, and tinted by status: orange needs you, green done, otherwise the character's colour. Dithering was tried and rejected.
- Never suggest committing, pushing or merging as the "next step". Hide the Next row when there is nothing real to say.
- Pick up closes the card at once. No success screen.
- Perch must never take the keyboard when it opens by itself, and never nudges about the session you are already in. A card you hover open takes it only when it shows something to answer; the details are in [keyboard.md](docs/behavior/keyboard.md).
- Motion should feel alive but rare. Respect `prefers-reduced-motion`.

## Things that will bite you

- `ui/app.js` is kept ASCII-only (non-ASCII as `\uXXXX`) because the file is loaded without a charset in places. After editing, check: `python3 -c "print(all(ord(c)<128 for c in open('ui/app.js').read()))"`.
- WebKit sends a card hovered open no pointer moves until it is clicked. Perch passes the pointer to the page (`cursor`), which marks what is under it `.hv` (`hoverAt`). Tailwind's `hover:` also matches `.hv`; a hand-written `:hover` rule in `input.css` needs a `.hv` twin.
- JS name clashes are silent: a second `var COLORS` once broke status colours. Check names before adding globals.
- Words or a mark that change in place go through the motion helpers at the top of `app.js` (`iconSwap`, `swapText`, `morphText`, `crossSeen`/`crossIn`, from transitions.dev; their styles end `input.css`). The snapshot comes again every refresh, so set each piece once per snapshot with its final value: setting a placeholder first and then the real words makes them swap on every refresh.
- Browsers cache `dist/ui.css` and `app.js` hard. In the design page, reload with `fetch(url, {cache: 'reload'})` after rebuilding CSS (`cd ui && npm run build`).
- Tailwind classes are generated from strings in `app.js`. Rebuild CSS after adding classes.
- macOS TCC permissions are tied to the code signature: a test build signed another way than the installed Perch takes its permissions over, and macOS asks again after every Allow, so `run.sh` signs with Developer ID when the Mac has it. Without it or the "Perch Dev" certificate the app is signed ad hoc and macOS asks again after every build. An update signed another way drops Accessibility without a word ([updates.md](docs/behavior/updates.md)).
- Accessibility is needed for Command+Option and for pasting replies. `AXIsProcessTrusted()` can lag after granting; onboarding offers a restart.
- The panel is one fixed transparent window (480 x 440 plus a 10 pt overscan above the screen). Cards must fit inside it, the settings and onboarding cards too. Settings is a list of pages, each as tall as its rows: the list 288 pt (318 without Accessibility), Agents 428 with all seven agents (no more room: a line added there goes off the panel), Notifications 242 (320 with its menu open), General 371 with three displays and an external one (each more display adds 30), Send feedback up to 394 with its field full, files and a line in orange. Measure `.p-set .inner` and `.p-onb .inner` in the design page after adding a row.
- Self-signed and ad-hoc builds cannot register for launch at login reliably.
- Opening a notch app over full-screen apps depends on window level and collection behavior; see `NotchPanel`.
- Hooks only change behaviour once installed (Settings, Live status). Codex skips a new hook until you trust it once. Never write to `~/.claude/settings.json` or `~/.codex/hooks.json` except through `HookInstaller`, which only touches its own entries; for OpenCode and pi it writes and removes only its own file (`~/.config/opencode/plugins/perch.js`, `~/.pi/agent/extensions/perch.ts`, first line `// Perch:`). An installed plugin file is written again at launch when this Perch carries a newer one (`HookInstaller.upgrade`). Try the installer with `PERCH_HOME=<folder> .build/debug/Perch --install-hooks` (agent names after the flag limit it: `--install-hooks cursor`), and a plugin against a stand-in socket before it reaches real config.
- An agent or multiplexer started from inside another app's terminal (this one, an editor's) inherits that app's variables: Claude Code started that way records itself as the Claude app (`entrypoint: claude-desktop`) and drops out of the terminal list. `agents-demo.sh` starts herdr with `env -i` for this reason.
- A tool Perch runs has its output read while it runs, never after `waitUntilExit()`: a pipe holds 64 KB, and one that prints more (`git status` in a checkout with a couple of thousand changes) waits for room for good, and so does whatever waits on it (the first scan, which left the list on "Looking for your sessions"). Output nothing reads goes to `FileHandle.nullDevice`. `SessionScanner.run` stops a git slower than 5 s.
- Seeing the real panel: computer-use screenshots hide it. Use `screencapture -x -R 496,0,520,340 out.png` with keys sent by `osascript`, in the same command (a card that Perch opened by itself closes after 9 s).

## Where things are headed

Open ideas, roughly in order: approving Codex from the notch if its hooks ever run alongside its prompt, a sound and haptics option, launch at login that survives distribution.
