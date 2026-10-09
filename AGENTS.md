# Perch: guide for people and agents picking this up

Perch is a macOS notch app. When a developer comes back to their Mac, it tells them where they left off across their Claude Code and Codex sessions and lets them jump back in, reply, snooze, or change settings, all from the notch. It is a portfolio-quality project: the bar is delight, polish and restraint, not feature count. Four jobs, in order: where was I, jump back in, what needs me, answer from the notch. Only the Claude app (Code) and Codex are in scope; terminal sessions are not.

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

Sessions: one row per session, newest first, up to 15 (the list shows five and scrolls). Claude: the Claude app's own list (`~/Library/Application Support/Claude/claude-code-sessions`) decides, archived ones skipped; transcripts are `~/.claude/projects/*/<id>.jsonl`. Codex writes `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`; `codex exec` runs and subagent threads are skipped (`SessionDigest.headless`), thread names come from `~/.codex/session_index.jsonl`. A chat started without a project (Claude scratch workspace, Codex dated folder) is named by its title (`Recap.isFolderless`). While a session works, the card says what it last said it is doing and a Now row shows the step (`Activity.step`). Typing in the list narrows it (`ListFilter`). Tests in `SessionScanTests` build a fake home folder: add one there for any new way a session can go missing. Small talk with no tool use is skipped (`Recap.isTrivial`). App icons and Codex itself are found by bundle id: Codex can be installed as `Codex.app` or `ChatGPT.app`. Pick up opens `claude://code/continue?session=local_<id>` or `codex://threads/<id>`. The card's body is the agent's outcome (`Recap.outcome`), not your prompt. A file watcher (FSEvents) refreshes within about half a second.

Status, two sources. With live status on, hooks say exactly what happened (`LiveStatus.apply`) and win over the transcript. Claude's PermissionRequest hook runs alongside the app's own prompt, whichever answers first wins, so Perch can allow, deny or answer a question (`answers` in `updatedInput`). Codex's runs before its prompt, so Perch answers Codex at once with no decision and only shows the status. Without hooks, status is guessed from the transcript's shape (`Recap.statusAndNext`). Test the socket without touching any config: `echo '{"session_id":"…","tool_name":"Bash","tool_input":{"command":"ls"}}' | ~/.config/perch/hook claude PermissionRequest` (it waits for your answer on the card).

When Perch speaks up: only on return from a break, only if a session changed since you last saw it (finished, asked, stopped) and since your last break or within the last day (`WhileAway.newsSince`; older is history, and a guessed "needs you" from then reads as idle, `Project.settled`), never during a call, camera or presentation (`Quiet`), and never during a "Not now". "Seen" is per session, in UserDefaults: a second on the welcome card, a Pick up, or being the session you are in. The Claude app's own `lastFocusedAt` counts too: a session you had in front there since it changed is not news, and the one it focused last is the session you are in.

## Running and building

```bash
cd ui && npm install && cd ..       # once
./scripts/make-dev-cert.sh          # once: stable signing identity so macOS keeps permissions
./scripts/run.sh --show             # build and launch, show the card
./scripts/run.sh --idle 15          # welcome card after 15 s idle (testing). Relaunch without it afterwards.
swift test
./scripts/package.sh                # build/Perch.zip for sharing
```

Useful flags: `--show`, `--simulate`, `--setup`, `--onboarding` (replays it from the hello), `--demo`, `--idle <s>`, `--snapshot <dir>`, `--dump` (prints what the scan finds), `PERCH_TRACE=1` for state logging.

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
- The settings and onboarding cards must stay at or under about 300 pt tall (the panel is 320). Measure `.p-set .inner` and `.p-onb .inner` in the design page after adding a row.
- Hooks only change behaviour once installed (Settings, Live status). Codex skips a new hook until you trust it once. Never write to `~/.claude/settings.json` or `~/.codex/hooks.json` except through `HookInstaller`, which only touches its own entries.
- Seeing the real panel: computer-use screenshots hide it. Use `screencapture -x -R 496,0,520,340 out.png` with keys sent by `osascript`, in the same command (a card that Perch opened by itself closes after 9 s).

## Where things are headed

Open ideas, roughly in order: Claude-quality summaries when the `claude` CLI is logged in (on-device summaries are shallow), approving Codex from the notch if its hooks ever run alongside its prompt, notarized releases, a sound and haptics option, launch at login that survives distribution.
