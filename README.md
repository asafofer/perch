# Perch

A notch app for macOS that tells you where you left off in your Claude Code and Codex sessions, and lets you jump back in.

Hover the notch, come back from being away, or press ⌃⌥P. The card shows each project's last topic, what's happening (working, replied, waiting on you), and lets you reply or pick up in one key.

## Requirements

- A Mac with a notch, macOS 26 or later
- Xcode 26 (Swift toolchain), Node 20+ (for the Tailwind build)
- Claude Code and/or Codex, used as you normally would. Perch only reads their local session files.

## Run it

```bash
cd ui && npm install && cd ..
./scripts/make-dev-cert.sh   # once: a local signing certificate, so macOS remembers permissions between builds
./scripts/run.sh --show      # build, launch, and show the card right away
```

Other flags: `--idle <seconds>` shows the welcome card after that much idle time (default 1200), `--simulate` plays away-then-back, `--setup` shows setup, `--snapshot <dir>` writes PNGs of each state.

Tests: `swift test`.

## How it's built

- `Sources/PerchCore`: pure logic. The notch state machine, geometry, transcript parsing and recaps. No UI. Tested.
- `Sources/Perch`: the AppKit shell. A borderless panel over the menu bar with a `WKWebView`, hotkeys, hover, session scanning, on-device summaries (Apple Intelligence).
- `ui/`: the interface. Plain JS, Tailwind v3 and shadcn-style classes, Inter bundled. Swift sends JSON snapshots to `window.perch.apply(...)`; the page only draws and reports clicks.
- `ui/design.html`: the same UI with sample data and every state on one page. Open it in a browser to iterate on design without the app (`cd ui && python3 -m http.server`).

## Keys

| | |
|---|---|
| Hover the notch | Open the card |
| ⌃⌥P | Welcome card |
| ⌃⌥L | Other projects |
| Tab | Switch between the card and the list |
| Return | Pick up |
| R | Reply |
| N | Not now (30 min, 2 hours, tomorrow) |
| Esc | Close |

## Permissions

- **Accessibility** is needed to paste a reply into Claude or Codex for you. Without it the reply is copied and you paste it.
- **Files** access prompts appear the first time Perch reads a project folder.
- **Apple Intelligence** (optional) writes the summaries on your Mac.
