# Perch: guide for people and agents picking this up

Perch is a macOS notch app. When a developer comes back to their Mac, it tells them where they left off across their Claude Code and Codex sessions and lets them jump back in, reply, snooze, or change settings, all from the notch. It is a portfolio-quality project: the bar is delight, polish and restraint, not feature count. Four jobs, in order: where was I, jump back in, what needs me, answer from the notch. Sessions from the Claude app (Code), the Codex app, and Claude Code or Codex in any terminal.

Read this file first. `README.md` has install and usage.

## How the work is done here

1. **Show it in the design page first.** New UI or a visible change goes into `ui/design.html` (the real UI with sample data) and gets looked at before it is built into the app. The owner will say "build it" when approved. Small fixes and bugs can go straight in.
2. **Look at it before you say it is done.** Render the design page in a browser (`cd ui && python3 -m http.server 8765`, open `/design.html`) and check each state. Say plainly what you checked and what you did not. Mock-ups and README screenshots sit on Raycast wallpapers (`ui/wallpapers/`, from raycast.com/wallpapers): `./scripts/run.sh --snapshot <dir> --wallpaper ui/wallpapers/blue-distortion-1.webp`.
3. **Commits:** one-line messages, no mention of AI or co-authors. Commit after every working step.
4. **Tests must stay green:** `swift test`.

## Architecture

```
Sources/PerchCore   Pure logic, no UI, fully tested.
  NotchMachine        State machine: idle, open, switcher, restoring, setup, onboarding, settings.
  NotchGeometry       Panel and tab sizes, hover rects. Takes ScreenInfo so it is testable.
  Project, Transcript Session model, JSONL parsing (Claude Code and Codex), recap text, git parsing.
  LiveStatus          Hook events (HookEvent), what an agent asks (Ask: words for the card, the reply JSON), live status per session.
  SessionScan         SessionScanner: which sessions get a row (Claude app list, Codex threads), tail reading, caches. DesktopSessions.
Sources/Perch       The AppKit shell.
  main.swift          Launch flags, hotkeys, status item menu, first-run onboarding.
  NotchController     Owns the machine, the panel, the WKWebView, timers, hover, keys, refresh.
  RealSessionProvider Runs the SessionScanner, keeps per-app counts and what each card was built from.
  HookServer          Unix socket (~/.config/perch/perch.sock) the hooks post to; holds a request open until you answer. HookInstaller writes the hook entries.
  ClaudeComposer      A reply into a Claude app session through Accessibility, Claude's window left behind.
  AppleRecapEngine    On-device summaries (FoundationModels), cache, guards against bad output.
  Snapshot            The JSON Swift sends to the page. The page never decides anything.
  Preferences         UserDefaults: onboarded, character, enabled apps, idle minutes.
  HotkeyService       Carbon hotkeys and the Command+Option tap (needs Accessibility).
ui/                 The interface, plain JS and Tailwind v3 (shadcn-style classes), Inter bundled.
  app.js              All rendering. window.perch.apply(snapshot) draws; messages go back through
                      webkit.messageHandlers.perch. A browser-only dev harness (window.perchDev) runs it with sample data.
  input.css           Tailwind plus the notch, glow and character styles.
  design.html         The design page. Scenarios for every state.
```

Data flow: Swift decides state (`NotchMachine`), builds a `UISnapshot`, calls `window.perch.apply(json)`. The page draws and posts events (`confirm`, `snooze`, `reply`, `settings`, `onb`, `character`, `source`, `setting`, ...). Handle new events in `NotchController.userContentController`.

Sessions: one row per session, up to 15. The list goes by section, what needs you, today, earlier, newest first in each (`ListFilter.ordered`); a row leads with the session's title and how long ago; at the right, a ring for its status (`rowMark`: the spinner while it works, a check when it finished and you have not seen it, ? for a question, the prompt for a command waiting for your OK, ! for anything else waiting) and its project in grey. About five show at a time. Claude: the Claude app's own list (`~/Library/Application Support/Claude/claude-code-sessions`) decides, archived ones skipped; transcripts are `~/.claude/projects/*/<id>.jsonl`. Codex writes `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`; `codex exec` runs and subagent threads are skipped (`SessionDigest.headless`), thread names come from `~/.codex/session_index.jsonl`. A chat started without a project (Claude scratch workspace, Codex dated folder) is named by its title (`Recap.isFolderless`). While a session works, the card says what it last said it is doing and a Now row shows the step (`Activity.step`). Typing in the list narrows it (`ListFilter`). Reply shows the agent's own last message as written (`Project.said`, line breaks kept); a reply to a terminal clears the card and the notch gulps the words. A reply to a Claude app session goes in with Claude's window behind (`ClaudeComposer`: it presses the session's sidebar row, fills the ProseMirror field, presses Send, then goes back; the page's address must end in `local_<id>` before it writes and before Send, otherwise it falls back to pasting). It leans on Claude's page internals, so a Claude update can send it to the fallback. Without Accessibility, Send reads Allow and send and holds the reply until access is on. Tests in `SessionScanTests` build a fake home folder: add one there for any new way a session can go missing. Small talk with no tool use is skipped (`Recap.isTrivial`). App icons and Codex itself are found by bundle id: Codex can be installed as `Codex.app` or `ChatGPT.app`. Pick up opens `claude://code/continue?session=local_<id>` or `codex://threads/<id>`. A terminal session (`Project.terminal`) goes back to its tab while it runs (Terminal and iTerm2 by tty, Ghostty and cmux by folder, any other terminal by bringing it forward; found from the process table in `Terminals.swift`), and otherwise resumes with `claude --resume` or `codex resume` in the terminal you used last. Its icon carries a badge of that terminal. Permission asks in a terminal show on the card but are answered there. The card's body is the agent's outcome (`Recap.outcome`), not your prompt. A file watcher (FSEvents) refreshes within about half a second.

Status, two sources. With live status on, hooks say exactly what happened (`LiveStatus.apply`) and win over the transcript, except a stop: Claude sends no hook for Stop or Esc, so a transcript that ends in one after the last hook wins (`LiveStatus.holds`). Claude's PermissionRequest hook runs alongside the app's own prompt, whichever answers first wins, so Perch can allow, deny or answer a question (`answers` in `updatedInput`). Codex's runs before its prompt, so Perch answers Codex at once with no decision and only shows the status. Without hooks, status is guessed from the transcript's shape (`Recap.statusAndNext`). Test the socket without touching any config: `echo '{"session_id":"…","tool_name":"Bash","tool_input":{"command":"ls"}}' | ~/.config/perch/hook claude PermissionRequest` (it waits for your answer on the card). Post test questions this way, to an idle session: a message sent in a Claude session while its question is open dismisses the question.

While you work, an answer or a request in a session you are not in shows as a live activity: the notch grows with the session's name, what happened, and a row of buttons on Command+Option keys registered only while it shows (app.js `activity`; `./scripts/run.sh --activity` plays it). A finish folds away; a request folds to wings until answered.

When the welcome card speaks up: only on return from a break, only if a session changed since you last saw it (finished, asked, stopped) and since your last break or within the last day (`WhileAway.newsSince`; older is history, and a guessed "needs you" from then reads as idle, `Project.settled`), never during a call, camera or presentation (`Quiet`), and never during a "Not now". "Seen" is per session, in UserDefaults: a second on the welcome card, a Pick up, or being the session you are in. The Claude app's own `lastFocusedAt` counts too: a session you had in front there since it changed is not news, and the one it focused last is the session you are in.

## Running and building

```bash
cd ui && npm install && cd ..       # once
./scripts/make-dev-cert.sh          # once: stable signing identity so macOS keeps permissions
./scripts/run.sh --show             # build and launch, show the card
./scripts/run.sh --idle 15          # welcome card after 15 s idle (testing). Relaunch without it afterwards.
swift test
./scripts/package.sh                # build/Perch.zip for sharing
```

Useful flags: `--show`, `--simulate`, `--setup`, `--onboarding` (replays it from the hello), `--hello` (the hello beside the notch after setup), `--demo`, `--idle <s>`, `--snapshot <dir>`, `--dump` (prints what the scan finds), `PERCH_TRACE=1` for state logging.

## Design rules (the owner is firm about these)

- Linear-grade restraint. Neutral sans (Inter), tight tracking, sentence case, small type (card text 13 to 14 px), small call-to-action buttons.
- **No dividing lines.** No pulsing or glowing dots (the list's status rings have a faint, still glow; nothing else). No drawn icons where a real app icon exists (use the real Claude and Codex icons from `AppIcons`).
- The character is a soft plush shape with flat, matte eyes. Its depth is one SVG filter on the body (`coatFilter` in `app.js`): light from the top left, a rounded form, shade that deepens its colour, a rim of light, and from 30 px up a fuzzy edge and faint grain. Small, it keeps a crisp outline. Nothing else goes on the character. Shapes live in `SHAPES` in `app.js`.
- Glow is internal, soft, and tinted by status: orange needs you, green done, otherwise the character's colour. Dithering was tried and rejected.
- Never suggest committing, pushing or merging as the "next step". Hide the Next row when there is nothing real to say.
- Pick up closes the card at once. No success screen.
- Perch must never take the keyboard when it opens by itself, and never nudges about the session you are already in. A card you hover open takes it only when it shows something to answer (`cardTakesKeys`): otherwise a number or Esc lands in the agent's own prompt behind it, and Esc there dismisses the question.
- Motion should feel alive but rare. Respect `prefers-reduced-motion`.

## Things that will bite you

- `ui/app.js` is kept ASCII-only (non-ASCII as `\uXXXX`) because the file is loaded without a charset in places. After editing, check: `python3 -c "print(all(ord(c)<128 for c in open('ui/app.js').read()))"`.
- WebKit sends a card hovered open no pointer moves until it is clicked. Perch passes the pointer to the page (`cursor`), which marks what is under it `.hv` (`hoverAt`). Tailwind's `hover:` also matches `.hv`; a hand-written `:hover` rule in `input.css` needs a `.hv` twin.
- JS name clashes are silent: a second `var COLORS` once broke status colours. Check names before adding globals.
- Browsers cache `dist/ui.css` and `app.js` hard. In the design page, reload with `fetch(url, {cache: 'reload'})` after rebuilding CSS (`cd ui && npm run build`).
- Tailwind classes are generated from strings in `app.js`. Rebuild CSS after adding classes.
- macOS TCC permissions are tied to the code signature. Without the "Perch Dev" certificate the app is signed ad hoc and macOS asks again after every build.
- Accessibility is needed for Command+Option and for pasting replies. `AXIsProcessTrusted()` can lag after granting; onboarding offers a restart.
- The panel is one fixed transparent window (480 x 320 plus a 10 pt overscan above the screen). Cards must fit inside it.
- Self-signed and ad-hoc builds cannot register for launch at login reliably.
- Opening a notch app over full-screen apps depends on window level and collection behavior; see `NotchPanel`.
- The settings and onboarding cards must stay at or under about 300 pt tall (the panel is 320). Measure `.p-set .inner` and `.p-onb .inner` in the design page after adding a row.
- Hooks only change behaviour once installed (Settings, Live status). Codex skips a new hook until you trust it once. Never write to `~/.claude/settings.json` or `~/.codex/hooks.json` except through `HookInstaller`, which only touches its own entries.
- Seeing the real panel: computer-use screenshots hide it. Use `screencapture -x -R 496,0,520,340 out.png` with keys sent by `osascript`, in the same command (a card that Perch opened by itself closes after 9 s).

## Where things are headed

Open ideas, roughly in order: Claude-quality summaries when the `claude` CLI is logged in (on-device summaries are shallow), approving Codex from the notch if its hooks ever run alongside its prompt, notarized releases, a sound and haptics option, launch at login that survives distribution.
