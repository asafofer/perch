# Perch: guide for people and agents picking this up

Perch is a macOS notch app. When a developer comes back to their Mac, it tells them where they left off across their Claude Code and Codex sessions and lets them jump back in, reply, snooze, or change settings, all from the notch. It is a portfolio-quality project: the bar is delight, polish and restraint, not feature count.

Read this file first. `README.md` has install and usage.

## How the work is done here

1. **Show it in the design page first.** New UI or a visible change goes into `ui/design.html` (the real UI with sample data) and gets looked at before it is built into the app. The owner will say "build it" when approved. Small fixes and bugs can go straight in.
2. **Look at it before you say it is done.** Render the design page in a browser (`cd ui && python3 -m http.server 8765`, open `/design.html`) and check each state. Say plainly what you checked and what you did not.
3. **Commits:** one-line messages, no mention of AI or co-authors. Commit after every working step.
4. **Tests must stay green:** `swift test`.

## Architecture

```
Sources/PerchCore   Pure logic, no UI, fully tested.
  NotchMachine        State machine: idle, open, switcher, restoring, setup, onboarding, settings.
  NotchGeometry       Panel and tab sizes, hover rects. Takes ScreenInfo so it is testable.
  Project, Transcript Session model, JSONL parsing (Claude Code and Codex), recap text, git parsing.
Sources/Perch       The AppKit shell.
  main.swift          Launch flags, hotkeys, status item menu, first-run onboarding.
  NotchController     Owns the machine, the panel, the WKWebView, timers, hover, keys, refresh.
  RealSessionProvider Scans ~/.claude/projects and ~/.codex/sessions, caches digests and git.
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

Sessions: Claude Code writes `~/.claude/projects/*/*.jsonl`; the Claude app's own ids map via `~/Library/Application Support/Claude/claude-code-sessions`. Codex writes `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`. Pick up opens `claude://code/continue?session=local_<id>` or `codex://threads/<id>`. A session is "working" when its last record is an open agent turn and the file changed in the last 150 seconds. A file watcher (FSEvents) refreshes within about half a second.

## Running and building

```bash
cd ui && npm install && cd ..       # once
./scripts/make-dev-cert.sh          # once: stable signing identity so macOS keeps permissions
./scripts/run.sh --show             # build and launch, show the card
./scripts/run.sh --idle 15          # welcome card after 15 s idle (testing). Relaunch without it afterwards.
swift test
./scripts/package.sh                # build/Perch.zip for sharing
```

Useful flags: `--show`, `--simulate`, `--setup`, `--demo`, `--idle <s>`, `--snapshot <dir>`, `--dump` (prints what the scan finds), `PERCH_TRACE=1` for state logging.

## Design rules (the owner is firm about these)

- Linear-grade restraint. Neutral sans (Inter), tight tracking, sentence case, small type (card text 13 to 14 px), small call-to-action buttons.
- **No dividing lines.** No pulsing or glowing dots. No drawn icons where a real app icon exists (use the real Claude and Codex icons from `AppIcons`).
- The character is a flat shape with flat eyes. No shaders, no gradients on the character. Shapes live in `SHAPES` in `app.js`.
- Glow is internal, soft, and tinted by status: orange needs you, green done, otherwise the character's colour. Dithering was tried and rejected.
- Never suggest committing, pushing or merging as the "next step". Hide the Next row when there is nothing real to say.
- Pick up closes the card at once. No success screen.
- Perch must never take the keyboard when it opens by itself, and never nudges about the session you are already in.
- Motion should feel alive but rare. Respect `prefers-reduced-motion`.

## Things that will bite you

- `ui/app.js` is kept ASCII-only (non-ASCII as `\uXXXX`) because the file is loaded without a charset in places. After editing, check: `python3 -c "print(all(ord(c)<128 for c in open('ui/app.js').read()))"`.
- JS name clashes are silent: a second `var COLORS` once broke status colours. Check names before adding globals.
- Browsers cache `dist/ui.css` and `app.js` hard. In the design page, reload with `fetch(url, {cache: 'reload'})` after rebuilding CSS (`cd ui && npm run build`).
- Tailwind classes are generated from strings in `app.js`. Rebuild CSS after adding classes.
- macOS TCC permissions are tied to the code signature. Without the "Perch Dev" certificate the app is signed ad hoc and macOS asks again after every build.
- Accessibility is needed for Command+Option and for pasting replies. `AXIsProcessTrusted()` can lag after granting; onboarding offers a restart.
- The panel is one fixed transparent window (480 x 320 plus a 10 pt overscan above the screen). Cards must fit inside it.
- Self-signed and ad-hoc builds cannot register for launch at login reliably.
- Opening a notch app over full-screen apps depends on window level and collection behavior; see `NotchPanel`.

## Where things are headed

Open ideas, roughly in order: Claude-quality summaries when the `claude` CLI is logged in (on-device summaries are shallow), "waiting for a permission" and "hit an error" statuses, answering a question without opening the session in the background (`claude -p --resume`, `codex exec resume`), notarized releases, more sources (Cursor, terminals), a sound and haptics option, launch at login that survives distribution.
