# Sessions: the list, where they come from, Pick up

The card's words are in [card.md](card.md), replying in [replies.md](replies.md), OpenCode, pi, Conductor and the multiplexers in [agents.md](agents.md).

## The list

- One row per session, up to 15. About five show at a time.
- It goes by section, what needs you, today, earlier, newest first in each (`ListFilter.ordered`). Typing in the list narrows it (`ListFilter`).
- A row leads with the session's title and how long ago. At the right, a ring for its status (`rowMark`: the spinner while it works, a check when it finished and you have not seen it, ? for a question, the prompt for a command waiting for your OK, ! for anything else waiting) and its project in grey.
- A file watcher (FSEvents) refreshes within about half a second.

## Where sessions come from

- Claude: the Claude app's own list (`~/Library/Application Support/Claude/claude-code-sessions`) decides, archived ones skipped. Transcripts are `~/.claude/projects/*/<id>.jsonl`.
- Codex writes `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`. `codex exec` runs and subagent threads are skipped (`SessionDigest.headless`). Thread names come from `~/.codex/session_index.jsonl`.
- Codex 0.162's terminal app writes `source: "vscode"` like the Codex app; `originator: "codex-tui"` is what says terminal.
- A chat started without a project (Claude scratch workspace, Codex dated folder) is named by its title (`Recap.isFolderless`).
- Small talk with no tool use is skipped (`Recap.isTrivial`), except in a terminal while its agent still runs there (`Project.smallTalk`: the scan keeps it marked, `RealSessionProvider` matches it to the running agents with the rest and drops it if none runs it), so a "hello" the notch just spoke of does not vanish as its reply lands.
- App icons and Codex itself are found by bundle id: Codex can be installed as `Codex.app` or `ChatGPT.app`.
- Tests in `SessionScanTests` build a fake home folder: add one there for any new way a session can go missing.

## Pick up

- The Claude app opens `claude://code/continue?session=local_<id>`, the Codex app `codex://threads/<id>`.
- A terminal session (`Project.terminal`) goes back to where it runs while it runs, found from the process table in `Terminals.swift`:
  - a herdr or tmux pane or cmux surface, exactly;
  - Terminal and iTerm2 by tty, Ghostty by folder;
  - Warp by switching tabs with Command+1 to 9 and reading each one's title and text through Accessibility (`WarpTabs`: Warp has no way to be asked, so it needs Accessibility, and reaches the first nine tabs of a window);
  - any other terminal by bringing it forward.
- One running where Perch cannot follow brings forward the terminal you used last and is never started a second time.
- A terminal session that no longer runs opens again where it last ran (`Restorer.reopen`, `Prefs.places`) with its agent's resume command, else in the terminal you used last.
- Its icon carries a badge of that terminal.
