<p align="center">
  <img src="docs/assets/icon.svg" width="128" alt="">
</p>

<h1 align="center">Perch</h1>

<p align="center">
  <strong>Where you left off, in the notch.</strong><br>
  For people who run several Claude Code, Codex, OpenCode and pi sessions at once.
</p>

<p align="center">
  <img alt="macOS 26+" src="https://img.shields.io/badge/macOS-26%2B-black?logo=apple&logoColor=white">
  <img alt="Apple silicon" src="https://img.shields.io/badge/Apple%20silicon-required-black">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white">
  <img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-black">
</p>

<p align="center">
  <a href="https://perchapp.dev">perchapp.dev</a> ·
  <a href="#features">Features</a> ·
  <a href="#install">Install</a> ·
  <a href="#shortcuts">Shortcuts</a> ·
  <a href="#privacy-and-permissions">Privacy</a> ·
  <a href="#development">Development</a>
</p>

<p align="center">
  <img src="docs/assets/perch.gif" width="720" alt="Perch in the notch: Claude asks to run a command, a flip to a session at work with its orb beside the step, all sessions with their status rings, then a session you are not in finishing while you work">
</p>
<p align="center"><sub>The real interface with sample data, on a wallpaper by <a href="https://www.raycast.com/wallpapers">Raycast</a>.</sub></p>

## Why Perch

Agents work while you are away, and they finish, stall or wait for an answer on their own schedule. When you come back to your Mac, Perch answers one question from the notch: **what was I doing, and what is waiting for me?** Then it gets you back in with one key.

## Features

- **Where was I.** After a break, a card drops from the notch with the session, its project, what the agent did and the next step when there is a real one. While a session works, it says what it is doing right now.
- **While you work.** When a session you are not in finishes or asks for something, the notch grows with what happened and a row of buttons. A finish folds away on its own; a request folds to small wings until you answer. An answer from the notch or a card says it went: the notch folds to one line that reads Sent, with a blue paper plane.
- **What needs you.** With live status on, Claude Code, Codex, OpenCode and pi tell Perch the moment they finish or need your OK. Sessions that need you come first.
- **Answer from the notch.** Allow or deny a command, or pick an answer to Claude's or OpenCode's question, without leaving what you are doing.
- **Jump back in.** One key opens the exact session: in the Claude app, in Codex, in the terminal tab it runs in, or the exact herdr pane or cmux split. A session that has ended opens again where it last ran.
- **Reply.** See the agent's last message and answer it, into a terminal session or into the Claude or Codex app.
- **All sessions.** Every recent session in one list, grouped into what needs you, today and earlier, with its status at a glance. Type to filter.
- **Yours.** Pick a character and its colour. It lives behind the notch and only comes out when there is something to say.

Perch never takes the keyboard unless you ask for it, and it stays quiet about the session you are already in.

**Works with** the Claude app (Code), the Codex app, [Conductor](https://conductor.build) (its Claude Code and Codex workspaces), and Claude Code, Codex, [OpenCode](https://opencode.ai) or [pi](https://pi.dev) in any terminal, with exact tab switching in Terminal, iTerm2, Ghostty and cmux, and exact panes inside [herdr](https://herdr.dev).

## Install

| Requirement | |
|---|---|
| macOS | 26 or later, on Apple silicon. A notch is optional: other displays get a small tab at the top centre. |
| Agents | The Claude app, the Codex app, Conductor, or Claude Code, Codex, OpenCode and pi in a terminal (herdr and cmux included). |
| To build | Xcode 26 and Node 20 or later. |

**Download.** Get `Perch.dmg` from the [latest release](https://github.com/asafofer/perch-releases/releases/latest), open it and drag Perch onto Applications (the window shows you where). Builds are not notarized yet, so the first time macOS says it can't check Perch: open System Settings, Privacy & Security, scroll down and choose **Open Anyway** beside Perch. After that Perch keeps itself up to date: it checks once a day, installs a new version in the background and restarts when nothing is on screen (the menu has Check for updates).

**Build from source.**

```bash
git clone https://github.com/asafofer/perch.git && cd perch
./scripts/make-dev-cert.sh   # once: a stable local signing identity, so macOS remembers permissions
./scripts/install.sh         # builds a release, installs it to /Applications and opens it
```

On first launch, a short setup walks you through your character, Accessibility, which apps to read and live status. You can run it again from Settings.

## Shortcuts

| Action | Keys |
|---|---|
| Open the card | Hover the notch, or tap <kbd>⌘</kbd> <kbd>⌥</kbd> |
| Where was I | <kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>P</kbd> |
| All sessions | <kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>L</kbd>, or <kbd>←</kbd> from the card |
| Next or previous session | <kbd>↑</kbd> <kbd>↓</kbd> |
| Open the session | <kbd>Return</kbd> |
| Allow or deny | <kbd>A</kbd> / <kbd>D</kbd> |
| Answer a question | <kbd>1</kbd> to <kbd>4</kbd> |
| Reply | <kbd>R</kbd> |
| Not now (30 minutes, 2 hours, tomorrow) | <kbd>N</kbd> |
| Settings | <kbd>⌘</kbd> <kbd>,</kbd> |
| Close | <kbd>Esc</kbd> |

While the notch shows something that finished or asks for you, its buttons answer to keys too, and only then: <kbd>⌘</kbd> <kbd>⌥</kbd> <kbd>Return</kbd> switches to it, <kbd>⌘</kbd> <kbd>R</kbd> replies, <kbd>⌘</kbd> <kbd>⌥</kbd> <kbd>Y</kbd> or <kbd>N</kbd> allows or denies, <kbd>⌘</kbd> <kbd>⌥</kbd> <kbd>1</kbd> to <kbd>3</kbd> answers, and <kbd>⌘</kbd> <kbd>⌥</kbd> <kbd>.</kbd> puts it away.

## Privacy and permissions

Perch reads the session files your agents already keep on your Mac and sends nothing anywhere. The card's words are your agents' own: the session's title, what the agent said it did, and a next step only when the agent stated one.

**Live status** is optional. It adds one hook entry to `~/.claude/settings.json` and `~/.codex/hooks.json` that runs `~/.config/perch/hook`, and for OpenCode and pi a plugin file of Perch's own (`~/.config/opencode/plugins/perch.js`, `~/.pi/agent/extensions/perch.ts`). They talk to Perch over a local socket only you can use and do nothing when Perch is not running. Your config files are backed up the first time as `*.before-perch`, and turning live status off removes the entries and files. Codex asks you once to trust a new hook.

| Permission | Used for | Without it |
|---|---|---|
| Accessibility | <kbd>⌘</kbd> <kbd>⌥</kbd>, and typing a reply into the Claude or Codex app | Replies are copied for you to paste |
| Automation | Switching to the exact terminal tab or cmux split and typing a reply into it | The terminal comes forward and you find the tab |
| Files | Reading project folders (macOS asks once per folder) | That project is skipped |

## How it works

```mermaid
flowchart LR
  A["Session files<br>~/.claude, ~/.codex, OpenCode, pi"] --> C["PerchCore<br>scan, parse, state"]
  B["Hooks (optional)<br>local socket"] --> C
  C --> D["Snapshot (JSON)"]
  D --> E["Web view in the notch<br>ui/app.js"]
  E -- "your choice" --> C
```

A native AppKit shell owns the notch panel, hotkeys and the hook socket. `PerchCore` decides everything (which sessions show, their status, what the notch does) and is fully tested. The interface is a small web view that only draws the snapshot it is given and reports what you chose.

## Development

Read [AGENTS.md](AGENTS.md) first: architecture, workflow, design rules and known pitfalls. [CONTRIBUTING.md](CONTRIBUTING.md) says how a change goes in and what CI checks.

```bash
cd ui && npm install && cd ..           # once
swift test                              # logic tests
./scripts/run.sh --show                 # build, launch and open the card
cd ui && python3 -m http.server 8765    # then open http://localhost:8765/design.html
```

`ui/design.html` is the real interface with sample data and every state on one page. New UI is designed there first.

| Path | Contents |
|---|---|
| `Sources/PerchCore` | State machine, geometry, session scanning, transcript parsing, live status. Pure and tested. |
| `Sources/Perch` | The AppKit shell: panel, web view, hotkeys, hook socket. |
| `ui/` | The interface: plain JavaScript and Tailwind, Inter bundled. |
| `scripts/` | Run, package, install, signing certificate, app icon and the README GIF. |

<details>
<summary><strong>Troubleshooting</strong></summary>

- **The card never appears on its own.** It waits until you have been away for the "Come back after" time, 20 minutes by default. To test it quickly: `./scripts/run.sh --idle 15`.
- **macOS asks for permissions after every build.** Run `./scripts/make-dev-cert.sh` once so builds are signed with a stable identity.
- **Accessibility is on but Perch still waits.** Remove Perch from the list with the minus button, add it again and restart Perch. Setup has a Restart button for this.
- **The list is empty.** `.build/debug/Perch --dump` prints what Perch finds in `~/.claude/projects`, `~/.codex/sessions`, OpenCode's database and `~/.pi/agent/sessions`, and which agents are running, in which terminal, herdr pane or cmux split. Headless runs (`claude -p`, `codex exec`) are not listed; `pi -p` and `opencode run` save sessions like any other, so they are.
- **Status lags or guesses.** Turn on live status in Settings. Without it Perch reads the transcripts, which can only guess when an agent is waiting for you.

</details>

<details>
<summary><strong>Release tooling</strong></summary>

| Script | What it does |
|---|---|
| `./scripts/package.sh` | Builds a release and writes `build/Perch.zip` for sharing. |
| `./scripts/release.sh` | Builds, signs the update with Perch's Sparkle key and writes the appcast; `--publish` pushes it to the releases repo. |
| `./scripts/make-icon.sh` | Renders `docs/assets/icon.svg` into the app icon and `icon.png`. |
| `./scripts/record.sh` | Films the design page's sample flow into `docs/assets/perch.gif`. Needs `ffmpeg`; headless. |
| `./scripts/agents-demo.sh` | herdr with pi, OpenCode, Claude Code and Codex side by side, and pi alone, in cmux, for trying Perch live. |

</details>

## Roadmap

- More sources: Cursor, tmux
- Notarized releases with automatic updates
- An optional sound and haptics

## Credits

Wallpapers by [Raycast](https://www.raycast.com/wallpapers). The working orb is [Thinking Orbs](https://thinkingorbs.com) by Yogesh (MIT). Set in [Inter](https://rsms.me/inter/) (SIL Open Font License 1.1, `ui/dist/fonts/OFL.txt`).

## License

[MIT](LICENSE).
