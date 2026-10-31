# Other agents, multiplexers and Conductor

OpenCode, pi and Muse as sources (Cursor, an app like Claude and Codex, is in [sessions.md](sessions.md)), herdr, tmux, cmux and agterm as hosts, which process is which session, and Conductor. Claude and Codex sources are in [sessions.md](sessions.md).

## OpenCode

- Every session, its desktop app's too, is in `~/.local/share/opencode/opencode.db` (SQLite, WAL, opened read-only per scan).
- OpenCode 1 writes `session`, `message` and `part`. OpenCode 2 writes `session_v2` and `session_message`, and copies 1's sessions there when it first runs. Both are read; for a session in each, 2's row wins.
- An OpenCode 2 message keeps its parts in `content`, and a turn ends in an `idle` message whose outcome says how (succeeded, interrupted, failed). `OpenCodeStore.message` puts 2's messages in 1's shape for `OpenCodeTranscript.digest`, and `pullRequestRecords` gives 2's tool calls in 1's shape (`callID`).
- OpenCode 2 renamed tools: `bash` is `shell`, `task` is `subagent`, and files are `path`.
- Subagent sessions (`parent_id`), archived ones and ones nobody wrote in are skipped. A placeholder title ("New session - …") gives way to your first prompt.
- Resume with `opencode -s <id>`.

## pi

- pi writes `~/.pi/agent/sessions/--<folder>--/<time>_<id>.jsonl`. The first line has the id and folder; entries form a tree but are always appended.
- The title is the newest `session_info` name, else your first prompt.
- Resume with `pi --session <id>`.

## Muse

- Muse Code (Meta) writes `~/.local/share/muse/sessions/YYYY/MM/DD/<id>/session.jsonl`, sharded by local date: one envelope a line (`stream.id` the session, `recorded_at` in microseconds). What was said is in `runtime.session` records whose `payload.kind` is `run`: `started` (your prompt), `assistant_message_committed`, `assistant_tool_calls_committed`, `tool_result_batch_committed` and `terminal` (`completed`, `cancelled`, else failed). Task and reminder records share the stream and are skipped (`MuseTranscript`).
- The folder is `runtime.session.metadata`'s `workspace_root`, near the top. Only the terminal app writes `session.startup_phases.observed`, so `muse exec` runs get no row; subagents have their own logs under `subagent/`.
- The title is the one Muse made in its index, `session-index.db` (`effective_long_title`, read-only, best effort), else your first prompt.
- Its hooks are Claude Code's shape in `~/.config/muse/settings.json` (which needs `"schema_version": 1`), all async ([status.md](status.md)).
- The process table shows the binary the `muse` launcher hands over to, `muse-bin-<version>`. Resume with `muse resume <id>`; a new session is `muse '<words>'`.
- Spike: [muse.md](../spikes/muse.md).

## herdr, tmux, cmux and agterm

- They host any agent. Every process in a herdr pane carries `HERDR_PANE_ID`, `HERDR_SOCKET_PATH` and `HERDR_SESSION`; in tmux `TMUX` (socket, server pid, session) and `TMUX_PANE`; in cmux `CMUX_SURFACE_ID` and `CMUX_WORKSPACE_ID`; in agterm `AGTERM_WINDOW_ID`, `AGTERM_SESSION_ID` and `AGTERM_PANE_ID`. `LiveSessions` reads them from the process's own environment (`KERN_PROCARGS2`). herdr wins, then tmux, since their servers can inherit a cmux tab's values.
- herdr: a server runs apart from any terminal, so the terminal you see it in is the one running a `herdr` client for that session (`LiveSessions.Viewer`). With none attached, Pick up opens one. herdr's own reading of each pane (working, blocked, done) counts below hooks and above the transcript (`HerdrStatus`).
- tmux is the same with its own CLI (`Tmux`, the server's executable from its pid, `-S` the socket):
  - one call per server lists its panes and clients (`TmuxServer.listing`);
  - Pick up moves the client already on the pane's session, else the one used last, to the pane (`switch-client -t %3`) and brings its terminal forward;
  - a reply is `send-keys` (copy mode left first);
  - the session you are in is the pane the front tab's client shows (`display-message -c`);
  - a session that ended opens again as a new window in its tmux session.
- cmux's command line tool only answers processes inside cmux (its default socket mode), so Perch drives cmux through AppleScript: a terminal's `id` is the `CMUX_SURFACE_ID` its processes carry. `input text` pastes (bracketed), so Return is sent separately with `perform action "text:\\r"`.
- agterm's command line tool, `agtermctl` (inside agterm.app), answers over agterm's socket from outside agterm too, so Perch drives agterm with it (`Agterm`), never AppleScript:
  - Pick up raises the session's window, selects the session (`session select`) and, in a split, shows it first when Cmd+D hid it (`session split visibility on`), then focuses the pane whose id the agent carries (`session focus`), left or right; a pane's id holds when the split's panes swap. It counts as exact only once that pane has the focus; a pane it cannot find or focus falls back to the tab, so a reply is never pasted into the split's other pane;
  - a reply is `session type --target <session> --pane-id`, the text after `--` so a reply starting with a dash is not read as an option, naming the session since agterm otherwise looks in the window's active one; its Return a beat later as its own key, since agterm types as keys do;
  - the session you are in is the focused pane of the active session in agterm's front window (`tree`);
  - a new session, or one that ended, opens as a new agterm session in its folder, your shell typing the agent's command, so the shell stays when the agent ends. agterm may take a few seconds to make its first window after it starts, so Perch retries for about five seconds, or fifteen when it just started agterm; when no session can be made, the session opens in Terminal instead (wherever Perch opens one in agterm, new sessions included);
  - with agterm's live sessions a pane's shell runs under a daemon, not under agterm, so an agent carrying agterm's ids with no app above it counts as agterm's. One with another app above it (an editor started from agterm) only inherited them and counts as that app's tab.

## Which process is which session

- One whose command names the session id, or that herdr names, else the newest session of that agent in that folder active since the process started (`Running.match`).
- Claude Code has three shapes in the process table: the native installer's `~/.local/share/claude/versions/<version>`, npm's 2.1 native binary `…/@anthropic-ai/claude-code/bin/claude.exe`, and an older npm `cli.js` under node with argv[0] `claude` (`Agent.recognise`, `Agent.mayBe`). One Perch does not recognise never counts as running: its card offers your last terminal and Pick up starts a second copy.

## Conductor

- Conductor (conductor.build) runs Claude Code and Codex in a git worktree per workspace and lists them in `~/Library/Application Support/com.conductor.app/conductor.db`: `sessions.claude_session_id` holds the Claude session id or the Codex thread id, `workspaces.workspace_path` the worktree.
- The transcripts are ordinary ones (Claude's entrypoint is `sdk-ts`, Codex's originator `codex_sdk_ts`). Conductor puts a `<system_instruction>` block before your first prompt, which `TranscriptParser.text` strips.
- `SessionScanner.claude` lists Conductor's own sessions and `codex` tags its threads (`Project.conductor`, the workspace id); archived workspaces and hidden sessions are skipped.
- A row carries Conductor's icon with the agent as a badge (`opens` in the snapshot, app.js `AppOf`).
- Pick up (`ConductorApp.open`) brings Conductor forward and presses the workspace's sidebar link through Accessibility: its address ends in `/workspace/<id>`, and Conductor has no `conductor://` link for an existing workspace. A project folded shut in the sidebar hides its links, so its row is clicked with the mouse (it offers no press action).
- The page's own address says which workspace is in front (`ConductorApp.showingNow`, for `youAreIn`).
- Reply goes in through the paste fallback: Conductor focuses its prompt on opening a workspace.
- A Conductor update that changes its page can leave Pick up at "Conductor, brought forward".

## Things that will bite you here

- herdr's `pane run`, `send-text` and `send-keys` print nothing when they work: judge herdr actions by exit status (`Herdr.act`). A herdr server brings its last layout back when it starts.
- An app started from a tmux pane (an editor opened with `code .`) passes `TMUX` and `TMUX_PANE` on to the shells in its own terminal, so an agent counts as in a tmux pane only when its tty is that pane's (`#{pane_tty}`). tmux's server runs apart from any terminal: before tmux was known, an agent in it had no terminal above it and Pick up started a second copy in a new window.
- macOS hides the environment of system binaries (`/bin/sleep`) from `KERN_PROCARGS2`; agents are not system binaries. node renames itself (pi's argv[0] is `pi`) and leaves empty strings where its arguments were.

## Tests

- `OtherAgentsScanTests`: a real SQLite file and pi files in a fake home.
- `ConductorScanTests`: the database and transcripts.
