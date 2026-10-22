# Sessions: the list, where they come from, Pick up

The card's words are in [card.md](card.md), replying in [replies.md](replies.md), OpenCode, pi, Conductor and the multiplexers in [agents.md](agents.md).

## The list

- One row per session, up to 15. About five show at a time.
- It goes by section, what needs you, today, earlier, newest first in each (`ListFilter.ordered`). Sessions at work lead their section in a steady order, newest begun first, so two working at once do not trade places every time one writes; a session takes its place by last activity once it stops. Typing in the list narrows it (`ListFilter`).
- A row leads with the session's title and how long ago. At the right, a ring for its status (`rowMark`: the spinner while it works, a check when it finished and you have not seen it, ? for a question, the prompt for a command waiting for your OK, ! for anything else waiting) and its project in grey.
- A file watcher (FSEvents) refreshes within about half a second.
- Opened from nothing, the list opens on its top row in one step (`toggleSwitcher`), and once the card has grown the scrolling area is made again (app.js `opening`): after Open Claude, WebKit kept showing the list where it was scrolled last while the choice was at the top, out of sight, so the arrows seemed dead.

## Where sessions come from

- Claude: the Claude app's own list (`~/Library/Application Support/Claude/claude-code-sessions`) decides, archived ones skipped. So are its side chats (`spawnedFrom.btw`): one copies its session's transcript, so its row read just like the session and a reply from the notch landed in the side chat. Transcripts are `~/.claude/projects/*/<id>.jsonl`.
- Claude tasks (what was Cowork) and Claude chats come from what the Claude app keeps of claude.ai on this Mac, read only:
  - The lists: claude.ai's persisted react-query cache, one blob of `IndexedDB/https_claude.ai_0.indexeddb.blob` (Snappy,
    then V8's structured clone: `ClaudeCache`). Tasks from `cowork-remote-sessions` and `cowork-local-sessions`, with the
    app's own state (`running`, `awaiting` an approval, `idle`) and `unread`; chats from `chat_conversation_list` (30 newest).
  - What was said: the conversations opened lately on this Mac, in LevelDB's files (`https_claude.ai_0.indexeddb.leveldb`)
    and the blob folder (`ClaudeWords`, `LevelDB`). A task's is the Claude Code stream it ran, read like any transcript; a
    chat's, its message tree. Without it a finished task says "Not opened on this Mac yet" in grey.
  - A task you have looked at in the app is not news (`unread` false sets `focusedAt`). A chat is never news.
  - Its approvals and questions show read only: Perch's hooks do not reach tasks that run in the cloud.
  - Both are read at most every 5 s and not watched: the app rewrites them all the time.
  - Tasks start on, chats off (`Agent.onByDefault`).
- Codex writes `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`. `codex exec` runs and subagent threads are skipped (`SessionDigest.headless`). Thread names come from `~/.codex/session_index.jsonl`.
- Codex 0.162's terminal app writes `source: "vscode"` like the Codex app; `originator: "codex-tui"` is what says terminal.
- A chat started without a project (Claude scratch workspace, Codex dated folder) is named by its title (`Recap.isFolderless`).
- Small talk with no tool use is skipped (`Recap.isTrivial`), except in a terminal while its agent still runs there (`Project.smallTalk`: the scan keeps it marked, `RealSessionProvider` matches it to the running agents with the rest and drops it if none runs it), so a "hello" the notch just spoke of does not vanish as its reply lands.
- App icons and Codex itself are found by bundle id: Codex can be installed as `Codex.app` or `ChatGPT.app`.
- Tests in `SessionScanTests` build a fake home folder: add one there for any new way a session can go missing.

## Pick up

- The Claude app opens `claude://code/continue?session=local_<id>`, a task `claude://claude.ai/cowork/<cse_id>`,
  a chat `claude://claude.ai/chat/<uuid>`; the Codex app `codex://threads/<id>`.
- A terminal session (`Project.terminal`) goes back to where it runs while it runs, found from the process table in `Terminals.swift`:
  - a herdr or tmux pane or cmux surface, exactly;
  - Terminal and iTerm2 by tty, Ghostty by folder (with several of its terminals in that folder, the first is a guess);
  - Warp by switching tabs with Command+1 to 9 and reading each one's title and text through Accessibility (`WarpTabs`: Warp has no way to be asked, so it needs Accessibility, and reaches the first nine tabs of a window);
  - any other terminal by bringing it forward.
- Only the first two, and a Warp tab that shows words only that session has or, in Warp's only window, is the only tab that fits (`WarpTabs.sure`), count as the session's own tab (`Terminals.Shown.exact`). A reply is pasted only there; anywhere else it stays on the clipboard (Reply copied), so it never lands in whichever tab was in front, and you are put back where you were rather than left in a tab that may be another session's.
- One running where Perch cannot follow brings forward the terminal you used last and is never started a second time.
- A terminal session that no longer runs opens again where it last ran (`Restorer.reopen`, `Prefs.places`) with its agent's resume command, else in the terminal you used last.
- Its icon carries a badge of that terminal.
