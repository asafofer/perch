<p align="center">
  <img src="docs/assets/icon.svg" width="120" alt="Perch">
</p>

<h1 align="center">Perch</h1>

<p align="center">
  A notch app for macOS that shows where you left off in Claude Code and Codex,<br>
  and lets you pick up, reply or snooze without leaving the notch.
</p>

<p align="center">
  <img alt="macOS 26+" src="https://img.shields.io/badge/macOS-26%2B-black?logo=apple&logoColor=white">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white">
  <img alt="Status: internal" src="https://img.shields.io/badge/status-internal-lightgrey">
</p>

<p align="center">
  <img src="docs/assets/card.png" width="400" alt="The welcome-back card"> &nbsp;
  <img src="docs/assets/list.png" width="400" alt="Other projects">
</p>

## Overview

Developers run several agent sessions at once and lose their place when they step away. Perch lives in the notch and answers one question when you come back: **what was I doing, and what is waiting for me?**

- **Welcome back.** After you have been away, a card drops from the notch with what you were working on, what the agent is doing now (working, replied, waiting on you) and the next step when there is a real one.
- **Pick up.** One key opens the exact Claude Code or Codex session.
- **Reply.** Answer from the card. Perch opens the session, pastes your reply and sends it.
- **Other projects.** A list of recent sessions with a live "working" indicator.
- **Private by design.** Summaries are written on your Mac by Apple Intelligence. Perch reads local session files and sends nothing anywhere.
- **Yours.** Choose your character's shape and colour in onboarding or Settings.

Perch never takes the keyboard when it opens on its own, and it stays quiet about the session you are already in.

## Requirements

| | |
|---|---|
| macOS | 26 or later, Apple silicon. A notch is optional: other screens get a small tab at the top centre. |
| Build tools | Xcode 26 and Node 20+ (for the Tailwind build) |
| Agents | Claude Code and/or Codex. Perch only reads their local session files. |

## Installation

**From source** (recommended while Perch is internal):

```bash
git clone https://github.com/asafofer/perch.git
cd perch
./scripts/make-dev-cert.sh   # once: a local signing certificate so macOS remembers permissions
./scripts/install.sh         # builds a release app, installs it to /Applications and opens it
```

**From a release:** download `Perch.zip` from the [latest release](https://github.com/asafofer/perch/releases/latest), unzip, then right-click `Perch.app` and choose **Open**. Builds are not notarized yet.

**Package your own build:** `./scripts/package.sh` writes `build/Perch.zip`.

On first launch Perch walks you through setup: character, Accessibility, which apps to read, and on-device summaries. You can replay it any time from Settings.

## Usage

| Action | Shortcut |
|---|---|
| Open the card | Hover the notch (or the tab) |
| Open or close Perch | Tap Command + Option |
| Welcome card | Control + Option + P |
| Other projects | Control + Option + L |
| Switch between the card and the list | Tab |
| Pick up the session | Return |
| Reply | R |
| Not now (30 min, 2 hours, tomorrow) | N |
| Settings | , |
| Close | Esc |

The menu bar item also offers the welcome card, other projects, app choices, character, setup and quit.

## Permissions

| Permission | Why | Without it |
|---|---|---|
| Accessibility | Command + Option, and pasting a reply into Claude or Codex | A reply is copied for you to paste |
| Files | Reading project folders (macOS asks once per folder) | That project is skipped |
| Apple Intelligence | On-device summaries (optional) | Plain recaps from the transcript |

If Accessibility is switched on but Perch still shows "waiting", remove Perch from the list with the minus button, add it again and restart Perch. Onboarding has a Restart button for this.

## Development

Start with [AGENTS.md](AGENTS.md): architecture, workflow, design rules and known pitfalls.

```bash
cd ui && npm install && cd ..
swift test                              # logic tests
./scripts/run.sh --show                 # build, launch and show the card
cd ui && python3 -m http.server 8765    # then open http://localhost:8765/design.html
```

`ui/design.html` is the real interface with sample data and every state on one page. New UI is designed there first.

| Path | Contents |
|---|---|
| `Sources/PerchCore` | State machine, geometry, transcript parsing and recaps. Pure and tested. |
| `Sources/Perch` | AppKit shell: panel, web view, hotkeys, session scanning, on-device summaries. |
| `ui/` | The interface: plain JavaScript, Tailwind and shadcn-style classes, Inter. |
| `scripts/` | Build, run, package, install and certificate scripts. |

## Troubleshooting

- **The card never appears on its own.** It needs you to be away for the "Come back after" time (20 minutes by default). To test quickly: `./scripts/run.sh --idle 15`.
- **macOS asks for permissions again after every build.** Run `./scripts/make-dev-cert.sh` once so builds are signed with a stable identity.
- **The list is empty.** `.build/debug/Perch --dump` prints what Perch finds in `~/.claude/projects` and `~/.codex/sessions`.

## Roadmap

Claude-quality summaries, "waiting for permission" and "hit an error" statuses, sending a reply in the background, notarized releases, more sources (Cursor, terminals). See [AGENTS.md](AGENTS.md).
