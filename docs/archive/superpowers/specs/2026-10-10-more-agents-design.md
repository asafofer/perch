# More agents and multiplexers: OpenCode, pi, herdr, cmux

Perch knows Claude Code and Codex, in their apps or any terminal. This adds two agents (OpenCode, pi) and two multiplexers (herdr, cmux) that host any of the four. The four jobs stay the same for every session: where was I, jump back in, what needs me, answer from the notch.

## What the tools are (checked on this Mac, 2026-10-10)

### OpenCode (agent; 1.18.35, Homebrew)

- Sessions: SQLite, `~/.local/share/opencode/opencode.db` (WAL), shared with the OpenCode desktop app (`ai.opencode.desktop`, URL scheme `opencode://`). `opencode db path` prints it.
- `session`: `id` (`ses_…`), `directory`, `title` (generated; a session nobody wrote in keeps "New session - <ISO date>"), `parent_id` (subagents), `time_archived`, `time_created`, `time_updated` (ms).
- `message`: `session_id`, `time_created`, `data` JSON: `role`, `time.completed` (absent while it streams), `finish` (`tool-calls` mid-turn, `stop` done), `error` (an abort, or a failure).
- `part`: `message_id`, `data` JSON: `text`, `reasoning`, `tool` (`tool`, `state.status` pending/running/completed/error, `state.input`), `step-start`, `step-finish`.
- Tool names are lowercase: `bash` (`command`, `description`), `read`/`edit`/`write` (`filePath`), `grep`, `glob`, `list`, `webfetch`, `websearch`, `task`, `todowrite`, `question`, plus MCP tools.
- Live status: a plugin file in `~/.config/opencode/plugins/` gets every bus event (`session.status` busy/idle/retry, `session.idle`, `session.error`, `permission.asked`/`permission.replied`, `question.asked`/`question.replied`/`question.rejected`, message and part updates) and an SDK client for the running server. The client can answer a permission (`once`, `always`, `reject`) and a question, so the notch can answer alongside OpenCode's own prompt.
- Resume: `opencode -s <id>`. The process is the `opencode` binary on a tty.

### pi (agent; 0.81.1 here, 1.1.0 current, both session format v3)

- Sessions: `~/.pi/agent/sessions/--<cwd, leading / dropped, / \ : as ->--/<ISO time>_<uuid>.jsonl`.
- First line: `{"type":"session","version":3,"id","timestamp","cwd"}`. Then entries with `id`/`parentId` (a tree; new entries are appended, so the tail is the live branch): `message`, `model_change`, `thinking_level_change`, `compaction`, `branch_summary`, `session_info` (`name`, set by `/name`), `label`, `custom`, `custom_message`.
- `message.message.role`: `user`, `assistant`, `toolResult`, `system` (1.x only, skipped). Assistant `content` blocks: `text`, `thinking`, `toolCall` (`name`, `arguments`). `stopReason`: `toolUse`, `stop`, `aborted`, `error` (with `errorMessage`).
- Tools: `bash` (`command`), `read`/`edit`/`write` (`path`), `grep`, `find`, `ls`.
- No permission prompts by design; an extension can show a prompt.
- Live status: an extension file in `~/.pi/agent/extensions/` (TypeScript, loaded on start). Events: `agent_start`, `tool_execution_start`, `agent_settled` (`aborted`), `ui_prompt_start`/`ui_prompt_end` (pi waits on you), `session_start`, `session_shutdown`. `ctx.sessionManager.getSessionId()` and `ctx.cwd` name the session.
- Resume: `pi --session <id>`. The process is node (or bun) with argv[0] `pi`.
- `pi -p` writes a session like an interactive one (only `--no-session` does not), with no marker.

### herdr (multiplexer; 0.9.3, Homebrew)

- A server that outlives the terminal (its parent is launchd) holds workspaces, tabs and panes; the `herdr` client attaches inside any terminal. Named sessions: `herdr session list --json`; sockets at `~/.config/herdr/herdr.sock` and `~/.config/herdr/sessions/<name>/herdr.sock`.
- Every pane process has `HERDR_ENV=1`, `HERDR_PANE_ID` (`w1:p2`), `HERDR_WORKSPACE_ID`, `HERDR_TAB_ID`, `HERDR_SESSION`, `HERDR_SOCKET_PATH`, `TERM_PROGRAM=herdr`.
- It recognises about 24 agents (claude, codex, opencode, pi among them) and classifies each: `idle`, `working`, `blocked` (an approval or question on screen), `done` (finished, not yet seen), `unknown`. `herdr agent list` returns JSON with `agent`, `agent_status`, `cwd`, `pane_id`, and `agent_session` when herdr's own integration for that agent is installed.
- Control: `herdr agent focus <pane>`, `herdr pane send-text`, `herdr pane send-keys <pane> enter`, `herdr tab create`, `herdr pane run`.
- Today Perch finds no terminal app above an agent in herdr, decides it is not running, and Pick up opens a second copy with `--resume`.

### cmux (multiplexer and terminal app; 0.64.2, `com.cmuxterm.app`)

- Already a Perch terminal, matched by folder (the first tab in that folder).
- Every surface's processes have `CMUX_WORKSPACE_ID` and `CMUX_SURFACE_ID`. The CLI (`/Applications/cmux.app/Contents/Resources/bin/cmux`) focuses an exact surface (`focus-panel --panel <surface> --workspace <ws>`) and types into one (`send --surface`, `send-key --surface … enter`).
- With cmux's own hooks on, `~/.cmuxterm/<agent>-hook-sessions.json` maps a session id to its workspace and surface, including agents cmux has hibernated (process stopped, tab kept; visiting the tab resumes it).

## Decisions (owner, 2026-10-10)

1. Icons: each project's own logo mark, bundled, for pi and for OpenCode; the real OpenCode.app icon when it is installed.
2. OpenCode's permission and question prompts are answerable from the notch.
3. In herdr, herdr's own status counts: below hooks, above guessing from the transcript.
4. A session that is no longer running reopens where it last ran (its herdr workspace, or cmux) when that is still open; otherwise in your last terminal, as today.

## Design

### Agents in one place

`Agent` in PerchCore describes each agent: id (`claude`, `codex`, `opencode`, `pi`), name ("Claude Code", "Codex", "OpenCode", "pi"), short name for sentences ("Claude", "Codex", "OpenCode", "pi"), the resume command for an id, and how to recognise its process (executable name or argv[0]). It replaces the `app == "codex" ? … : …` choices spread through Recap, LiveStatus, Ask, NotchController, Restorer, main.swift, Preferences and the settings rows. No visible change.

### Where an agent lives

`LiveSessions` reads each agent process's argv and environment (`KERN_PROCARGS2`, same user, no permission) and records where it lives, innermost first:

- herdr pane: `HERDR_PANE_ID` and `HERDR_SOCKET_PATH` (wins over any `CMUX_*` the herdr server inherited).
- cmux surface: `CMUX_SURFACE_ID` and `CMUX_WORKSPACE_ID`.
- a terminal tab: its tty and the terminal app above it, as today.

Parsing the environment into a place is a pure function in PerchCore, tested there.

- Pick up, herdr: `herdr agent focus <pane>` on that session's socket, then bring forward the terminal that shows a client attached to that herdr session (a `herdr` process with a tty; the exact tab where the terminal allows it). No client attached: open your terminal running `herdr` for that session, which shows the focused pane.
- Pick up, cmux: focus the exact surface, then bring cmux forward.
- Reply: `herdr pane send-text` then `send-keys enter`; `cmux send` then `send-key enter`.
- A session that is no longer running: Perch remembers where each session last ran (session id to place, in UserDefaults). If that herdr session's server is running, a new tab in that workspace runs the resume command; if cmux holds the session's surface (its hook-sessions file), focus it and cmux resumes it; if cmux is open, a new cmux workspace; otherwise your last terminal.
- The row's icon badge and the Open button name the terminal you will see (the one showing herdr). The tooltip says "pi in herdr, in Ghostty".

### OpenCode source

- PerchCore opens the database read-only (SQLite3 from the SDK, no dependency). Sessions: no `parent_id`, not archived, updated within 14 days, at least one prompt from you, a usable folder. Newest first.
- Each session's last 40 messages and their parts become a `SessionDigest` (`OpenCodeTranscript.digest`): your last prompt, the agent's last text, the step from the newest tool part, `turnOpen` from `time.completed` and `finish`, `interrupted` from an abort error. Read again only when the session's `time_updated` changes.
- Title: the session's title, unless it is the default "New session - …"; then your first prompt.
- Terminal or app: the database does not say which one a session came from. Running on a tty, it is a terminal session. Not running: Pick up opens the OpenCode app if it is running, otherwise it resumes where it last ran.
- The file watcher adds `~/.local/share/opencode`.

### pi source

- Same tail reading as Codex: head for id and folder, tail for messages (`PiTranscript.digest`). `turnOpen` while the last assistant `stopReason` is `toolUse` and its results are not all in, `interrupted` on `aborted`, failed on `error`.
- Title: the newest `session_info` name, else your first prompt.
- The file watcher adds `~/.pi/agent/sessions`.

`Activity.step` and `Ask.describe` learn the lowercase tool names of both.

### Status from herdr

When a herdr server is running, `herdr agent list` on each session's socket gives every agent's state. An agent maps to a session by `agent_session` when herdr reports it, otherwise by agent and folder (the newest session there). `blocked` reads as needs you, `working` as working, `done` as finished. Hook status still wins; the transcript's guess only applies when neither says anything.

### Live status for OpenCode and pi

The Live status switch also installs, per enabled agent, Perch's own file and nothing else:

- `~/.config/opencode/plugins/perch.js`
- `~/.pi/agent/extensions/perch.ts`

Each file posts to the existing socket in Perch's own hook vocabulary (`UserPromptSubmit`, `PostToolUse`, `PermissionRequest`, `Stop`, `StopFailure`, `Interrupt`), so `HookEvent` changes little. Turning the switch off deletes the file. It exits quietly when Perch is not running.

- OpenCode asks: on `permission.asked` or `question.asked` the plugin opens a request Perch holds, without blocking OpenCode. Your answer comes back as the body; the plugin replies through OpenCode's client. If you answer in OpenCode first, `permission.replied` makes the plugin drop its request, and Perch settles the card (the existing abandoned path).
- pi: `ui_prompt_start` shows "pi is waiting on you" with the prompt's title, answered in the terminal; `ui_prompt_end` clears it.

### Interface (design page first)

- OpenCode and pi rows and cards, with their marks, in the list and on the card; a pi session running in herdr inside Ghostty; an OpenCode permission ask.
- Settings, Apps: four chips.
- Onboarding, apps step: only agents found on this Mac (installed or with sessions), so the card stays under 300 pt; measured in the design page.
- Status text follows the existing pattern: "OpenCode is working", "pi finished", "OpenCode wants to run a command", "pi is waiting on you".
- `FakeSessionProvider` gets the same samples as the design page.

## Testing

- SessionScanTests, in the fake home: an OpenCode database built in the test (a normal session, a subagent, an archived one, an empty one, a default title, an unusable folder) and pi files (a named session, an aborted one, a trivial one, an unusable folder).
- TranscriptTests: OpenCode and pi digests for working, finished, stopped and failed; steps for their tools.
- LiveStatusTests: the new agents' events and asks; the environment-to-place parser.
- Manual, with the owner (steps first, the owner says go): each agent in Ghostty, in cmux and in herdr; Pick up while running and after quitting; a reply; an OpenCode permission answered from the notch and in OpenCode.

## Order of work

1. Design page proposal. The owner says "build it".
2. `Agent` descriptions.
3. Where an agent lives: herdr and cmux panes, reopening where it last ran.
4. OpenCode source.
5. pi source.
6. Status from herdr.
7. Live status files for OpenCode and pi, answering OpenCode from the notch.
8. AGENTS.md and README.

## Out of scope

tmux and other multiplexers (the same environment reading would cover tmux later), OpenCode's web UI, remote herdr machines, cmux's Feed.
