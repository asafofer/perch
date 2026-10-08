# Perch

A notch app for macOS. When you come back to your Mac, Perch tells you where you left off in your Claude Code and Codex sessions, and lets you jump back in, reply, snooze, or change settings, all without leaving the notch.

- **Welcome back.** After you have been away, the card drops from the notch: what you were doing, what the agent is doing now (working, replied, waiting on you), and the next step when there is a real one.
- **Pick up.** Return opens the exact Claude Code or Codex session.
- **Reply.** Answer from the card. Perch opens the session, pastes your reply and sends it.
- **Other projects.** Tab shows your recent sessions with a live "Working" indicator.
- **On-device summaries.** Written by Apple Intelligence on your Mac. Nothing leaves it.
- **Yours.** Pick your character's shape and colour in onboarding or Settings.

## Requirements

- macOS 26 or later (Apple silicon). A notch is not required: on other screens Perch draws a small tab at the top centre.
- Xcode 26 (for the Swift toolchain) and Node 20+ (for the Tailwind build).
- Claude Code and/or Codex, used as you normally would. Perch only reads their local session files.

## Install

**From source (recommended while this is internal):**

```bash
git clone https://github.com/asafofer/perch.git
cd perch
./scripts/make-dev-cert.sh   # once: a local signing certificate so macOS remembers permissions
./scripts/install.sh         # builds a release app, copies it to /Applications, opens it
```

**Run it in development:** `./scripts/run.sh --show` (builds a debug app and shows the card straight away).

**Share a build:** `./scripts/package.sh` writes `build/Perch.zip`. It is not notarized, so whoever unzips it right-clicks Perch.app and chooses Open the first time.

On first launch Perch walks you through setup: character, Accessibility, which apps to read, and on-device summaries.

## Using it

| | |
|---|---|
| Hover the notch (or the tab) | Open the card |
| Command + Option, tap | Open or close Perch |
| Control + Option + P | The welcome card |
| Control + Option + L | Other projects |
| Tab | Switch between the card and the list |
| Return | Pick up |
| R | Reply |
| N | Not now: 30 min, 2 hours or tomorrow |
| , | Settings |
| Esc | Close |

Menu bar item: welcome card, other projects, choose apps, customize your character, set up Perch, quit.

## Permissions

- **Accessibility**: Command + Option, and pasting a reply into Claude or Codex for you. Without it, a reply is copied and you paste it yourself.
- **Files**: macOS asks the first time Perch reads a project folder. Choose Allow.
- **Apple Intelligence** (optional): on-device summaries.

If you toggled Accessibility on and Perch still says it is waiting, remove Perch from the list with the minus button, add it again, and restart Perch (onboarding has a Restart button for this).

## Developing

Read [AGENTS.md](AGENTS.md): architecture, the design-first workflow, design rules, and the gotchas. Short version:

```bash
cd ui && npm install && cd ..
swift test                         # logic tests
./scripts/run.sh --show            # build and launch
cd ui && python3 -m http.server 8765   # then open http://localhost:8765/design.html
```

`ui/design.html` is the real interface with sample data and every state on one page. New UI goes there first.

## Troubleshooting

- **Card never appears on its own:** it needs you to be away for 20 minutes (Settings, "Come back after"). For testing, `./scripts/run.sh --idle 15`.
- **macOS keeps asking for permissions after every build:** run `./scripts/make-dev-cert.sh` once.
- **Nothing in the list:** `.build/debug/Perch --dump` prints what Perch finds in `~/.claude/projects` and `~/.codex/sessions`.
