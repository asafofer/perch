# Spike: Herdr's app as a host

2026-11-01. Herdr 0.1.11 (`~/Applications/Herdr.app`, bundle id `dev.herdr.app`, signed by Herdr, Inc.) and herdr-core
(`hc`) 0.1.16 in `~/.local/bin`, from `releases.herdr.dev/app/install.sh`. Herdr is the desktop app on a new runtime; the
herdr CLI (0.9.x, `HERDR_*` variables) is a separate product and works as before. Everything below was driven with Claude
Code and Codex in the real app unless it says otherwise. What shipped is in [agents.md](../behavior/agents.md).

## In short

- **Running: works.** Every program in an hc terminal carries `HC_TERMINAL_ID` (`t2`) and `HC_TERMINAL_SOCKET`
  (`~/.local/state/herdr-core/default/default.sock`). It runs under `herdr-core hold`, which runs under `herdr-core serve`:
  no terminal app above it. It also says `TERM_PROGRAM=ghostty`, and passes on whatever environment its core started with.
- **Pick up: works.** `herdr-app do agent.focus --terminal t2` switches Herdr's window to that space and tab (about 6 ms) but
  does not bring Herdr forward, so Perch activates it too. A terminal that is in no tab (started with `hc run` alone)
  is not in the window: for a plain program `agent.focus` says `no running terminal`, and for an agent it says `ok` and shows nothing. Perch checks `herdr-app ls` first and attaches it in your terminal (`hc attach t7`).
- **Reply: works, Claude Code and Codex.** `hc send t2 "<words>"` pastes, waits for a pause and presses Return. Codex took it
  as one message. No tags are added when the sender is outside hc.
- **Status: ~.** `hc ls --json` gives each terminal's `agent` (`claude-code`, `zsh`) and, for agents that report it (OSC
  7501), `status`: Claude Code showed `done`, `idle`, and `blocked` while it waited on an approval or a question. Perch's hooks still come first.
- **The session you are in: works.** `herdr-app status` names the `focused_pane` (none under an overlay such as the welcome),
  and `herdr-app ls` says which terminal is in it.
- **Opening again: works.** `herdr-app do tab.new --folder <cwd>` returns the new terminal; `hc send` types the resume
  command into its shell. With no space yet, `space.new --folder`.
- **New session from the notch: works.** New session's Where step offers Herdr; Codex started in a new Herdr tab with its prompt.
- **Approvals and questions: shown, answered in Herdr.** Perch's hooks show them on the card (hc said `blocked`); as for every terminal, Perch does not hold the hook, and Open Herdr lands on the prompt.

## Traps

- An app opened from inside the Claude app (`open -a Herdr`) inherits its environment, and so do hc's core and every agent in it:
  Claude Code then says "Transcript saving is off — inherited CLAUDE_CODE_CHILD_SESSION marker". Start Herdr with `env -i … open`.
- `hc` without `HC_SESSION` reaches the default core; the session is the socket's name.
- Herdr's window shows the default core only. A terminal on another core (`HC_SESSION=work`) answers `hc send` and `hc attach` with that variable set.
- Codex's first start in a folder asks to trust its hooks; text sent then goes into that prompt.
