# Spike: Muse Code as a source

2026-10-31. Muse Code 1.4.14 (`1.4.14-R7309.1`, channel `muse-stable`), Meta's terminal coding agent, installed on this Mac
with the official installer (`curl -fsSL https://dev.meta.ai/install.sh | bash`). It is a command line tool only: no app, no
bundle id, no URL scheme. Docs: dev.meta.ai/docs/muse-code.

This Mac has no Meta login (`muse usage`: "not logged in", no `~/.config/muse/auth.json`, no `META_API_KEY`), so no real
model ran. Muse ships an `echo` provider that needs no login (`--provider echo`: it answers every prompt with
`echo: <prompt>` and calls no tools). Everything below marked **driven** was run with it, in a stand-in home
(`HOME=<scratch>/home`) and a scratch git folder, the TUI inside a private tmux server (`tmux -L musespike`), with no keys
sent. Marked **docs** comes from Meta's pages or from the skills Muse ships with itself (`read-session`, `create-plugin`).
Marked **binary** comes from strings in the Muse executable. None of those was driven.

## In short

The providers.md row, as far as this spike can say:

| Listed | Words and recap | Live status | Approvals from the notch | Questions from the notch | Reply | Pick up | New session | Pull requests |
|---|---|---|---|---|---|---|---|---|
| ✓ | ~ tool calls not driven | ✓ hooks | ~ not driven | ~ shows it asks; no way to answer found | ✓ typed into its pane or tab (not driven) | ✓ | ✓ | ~ from its log, not driven |

- **Listed: works.** Each session is a folder with a `session.jsonl`, and Muse keeps a SQLite index of them with title,
  folder and times. Driven.
- **Words: prompts, replies and turn ends are plain to read.** Driven. Tool calls and results have their own records
  (docs), not seen since the echo provider calls no tools.
- **Live status works through hooks**, in Claude Code's own shape, in `~/.config/muse/settings.json`. Perch's exact hook
  entry was accepted. SessionStart, UserPromptSubmit, Stop and SessionEnd driven; tool and approval events not driven.
- **Approvals: probably answerable, not proven.** A PermissionRequest hook can answer (`hookSpecificOutput.decision`
  with `behavior`, binary), but it fires before Muse's own approval judge decides, also for calls that never reach you.
  Notification fires 6 s later only when a request still waits on you (binary, from Muse's built-in herdr plugin).
- **Questions: Muse asks** (its `request_user_input` tool; Notification `question_prompt`, "Muse Code needs your input"),
  but no hook answer for a question was found.
- **Reply** is the terminal path every terminal agent uses. Its composer has bracketed paste on. Not driven: no keys were sent.
- **Pick up: `muse resume <id>`** reopened the exact session. Driven.
- **New session: `muse '<prompt>'`** in the folder starts the TUI with that prompt sent. Driven. A folder Muse has not
  seen asks first whether to trust it, in the terminal.
- **Pull requests:** a `gh pr create` result would sit in a `tool_result_batch_committed` record (docs). Not driven.

To finish the row the owner needs a Meta login on this Mac (see [Open](#open)).

**Code it would need:** `Agent.muse` (id `muse`, resume `muse resume`, `recognise` and `mayBe` for `muse-bin-*`); a
`MuseStore` beside `Pi.swift` reading the index and each `session.jsonl` into a `SessionDigest`; a scanner in
`SessionScan.swift`; `muse` in `HookServer.agents` and `HookInstaller` (Claude-shaped entries in
`~/.config/muse/settings.json`, keeping `schema_version`); its events in `LiveStatus`; the new session command in
`NewSession.swift`; `PullRequestScan` for its tool results. Answering approvals waits on a driven test.

## Install and process

- The installer puts a bash launcher at `~/.local/bin/muse` and the real binary beside it,
  `~/.local/bin/muse-bin-1.4.14-R7309.1` (424 MB). It changes no shell profile when `~/.local/bin` is already on PATH.
- The launcher checks for updates once an hour (in the background) and then `exec`s the binary. So the process table shows
  the binary, never `muse`:

  ```
  31954 /Users/asaf/.local/bin/muse-bin-1.4.14-R7309.1 --provider echo hello from the tui
  ```

  Executable name `muse-bin-<version>`, argv[0] the binary's full path. A resumed session carries its id in its arguments
  (`... resume 01a1921b-7cd6-7720-8c24-3b4ab1fcdbe8`). The process's working folder is where it was started.
- In tmux the process carries `TMUX` and `TMUX_PANE` as usual (read with `ps eww`), so `Place` finds its pane.
- Muse ships a herdr plugin of its own: inside a herdr pane (`HERDR_ENV=1`) it reports working, blocked and idle to herdr
  (binary). Perch's `HerdrStatus` should get that for free. Not driven.

## Where the data is

| | |
|---|---|
| Sessions | `${XDG_DATA_HOME:-~/.local/share}/muse/sessions/YYYY/MM/DD/<id>/session.jsonl`, sharded by local date. `<id>` is a UUIDv7 and the hooks' `session_id` |
| Also in that folder | `.session.lock`, `cron.db`, a `cli-<uuid>.log`, `subagent/<child id>/session.jsonl`, `tool-outputs/` for big tool output (docs) |
| Index | `~/.local/share/muse/session-index.db`, SQLite, WAL. Table `sessions`: `session_id`, `session_log_path`, `workspace_root`, `git_branch`, `title` (your first prompt), `effective_long_title` and `title_provenance` (`generated` or `manual`), `first_user_prompt`, `created_at_us`, `updated_at_us`, `prompt_count`, `status` (`valid`), `latest_segment_terminated` (0 while open or after a kill), `session_name`, `msp_kind` (`root`) |
| Names | Muse names each session itself (`ruby-calypso`, `session.name.changed`), and `/name` renames it. The claims live in `~/Library/Application Support/Muse/session-name-authority/session-names.db`, which Muse writes in the real home even when `HOME` points elsewhere |
| Settings | `~/.config/muse/settings.json` (needs `"schema_version": 1`); login in `~/.config/muse/auth.json` |
| Project config | `<project>/.muse/hooks.json`, `AGENTS.md`, `CLAUDE.md`, `.agents/memory/`, loaded only after you trust the folder (docs) |

- Only sessions with a turn get an index row. Runs that failed before a turn (no model reachable) left a session folder and
  no row.
- Subagents have their own logs under `subagent/` and no index row. Each turn ran three "reminder" subagents here
  (`skill-reminder`, `goal-reminder`, `verify-reminder`), so subagent folders are common.
- Headless sessions (`muse exec`) are indexed like interactive ones. Only the TUI writes `session.startup_phases.observed`
  (with a `terminal_probe` phase), which tells them apart.
- No archive. `session_retention_days` in settings deletes old sessions (docs).
- Opening the index with `sqlite3 -readonly` failed ("unable to open database file") once, after a headless run had
  closed it and no `-shm` was left; a copy opened fine, and read-only worked again while the TUI ran. A reader should not
  depend on it: the session files alone hold everything.

## Words (driven, echo provider)

Each line is an envelope: `schema_version`, `id`, `stream` (`{"kind":"session","id":<session id>}`), `sequence`,
`recorded_at` (microseconds since 1970), `record_type`, `payload_type`, `payload`. The first line is a wrapper with
`retained_frame` instead (a permission transaction holding records as strings), so a parser must skip what it does not know.

| Record | Where |
|---|---|
| Folder | `payload_type: runtime.session.metadata`, `payload.record.workspace_root` (also `provider_id`, `build.semver`) |
| Your prompt | `runtime.session` with `payload.event.kind: started`, text in `payload.event.prompt` |
| The reply | `payload.event.kind: assistant_message_committed`, `payload.event.text` |
| Turn end | `payload.event.kind: terminal`, `terminal: completed` (also `turn_duration_ms`) |
| Session end | `payload_type: session.end`, `exit_reason: clean`. A session whose terminal was closed writes nothing; the next resume writes `exit_reason: crash_inferred` first |
| Tool calls and results | `assistant_tool_calls_committed` and `tool_result_batch_committed`, names like `shell`, `write_file`, `edit_file`, `apply_patch` (docs, not seen) |
| A prompt typed mid-turn | `inbox_item_queued` with `source.source: user_steer` (docs) |

The log is heavy: one echo turn wrote 112 KB (context diagnostics, task records, reminder runs). Reading must start
from the tail.

## Hooks (driven, stand-in home)

Muse reads Claude Code's hook shape from `~/.config/muse/settings.json`:

```json
{"schema_version": 1,
 "hooks": {"Stop": [{"matcher": "*", "hooks": [{"type": "command", "command": "<script> muse Stop", "timeout": 10, "async": true}]}]}}
```

That is the entry `HookInstaller` already writes for Claude, and Muse took it without a warning. It reports what it
skipped on start (`muse: Hooks: 12 runnable · 2 warnings`): `ToolUseStart` and `Interrupt` must be `async: true`.

- Events (docs): SessionStart, UserPromptSubmit, PreToolUse, PermissionRequest, PostToolUse, PostToolUseFailure,
  PostToolBatch, PreLLMCall, PostLLMCall, PreCompact, PostCompact, SubagentStart, SubagentStop, Notification, Stop,
  StopFailure, SessionEnd; also ToolUseStart and Interrupt (binary, used by its herdr plugin).
- One prompt fired, in order: SessionStart (`source: startup`), UserPromptSubmit (`prompt`, `turn_id`), Stop
  (`last_assistant_message`, `stop_hook_active`), then SubagentStart and SubagentStop for the reminders, and SessionEnd
  for a headless run. A resumed TUI fired nothing until a prompt was sent.
- Every payload: `hook_event_name`, `session_id`, `cwd`, `model`, `permission_mode` (`default`), and `transcript_path`,
  always null. Subagent events carry the **child's** id as `session_id` (with `subagent_id`, `child_session_id`), so they
  must not be read as the session's own.
- The hook runs with a cleared environment: `HOME`, `PATH`, `TERM`, `PWD`, `MUSE_SESSION_ID`, `MUSE_THREAD_ID`,
  `TRACEPARENT`. Perch's script needs only `HOME` and `$PPID`; for a plain command `$PPID` is the Muse process.
- A hook without `async` blocks: a 3 s UserPromptSubmit made the turn 3 s longer.
- Muse does not run Claude Code's or Codex's hooks: with `~/.claude/settings.json` and `~/.codex/hooks.json` in the
  stand-in home, trusted folder or not, only Muse's own fired. No double reports.
- Project hooks (`.muse/hooks.json`) run only in a trusted folder; user hooks always run (docs).

## Approvals and questions (not driven: needs a real model)

- Modes (docs): `--approval-mode on-request` (default: known safe shell steps run in the sandbox, dangerous ones stop),
  `untrusted`, `never`. Sessions start in the Auto-review profile, where an LLM judge decides and asks you only when it
  cannot; `--approval-judge off` sends every decision to you. Your choices: Allow once, Always allow in this workspace, Reject.
- Hook answers (binary, from the messages Muse prints for a wrong answer): PermissionRequest takes
  `hookSpecificOutput.decision` as a string or an object with `behavior`. PreToolUse takes
  `hookSpecificOutput.permissionDecision`; a bare `allow` is refused unless it carries `updatedInput`, and `deny` needs a
  `permissionDecisionReason`.
- The catch (binary, comments in Muse's herdr plugin): PermissionRequest fires before the decision, including for calls
  the judge settles itself and for the reminders' own tool. Notification fires after a 6 s deadline, only if the request
  still waits on you, with `notification_type` `permission_prompt` ("Muse Code needs approval") or `question_prompt`
  ("Muse Code needs your input"). So Notification is the honest "needs you" signal, and holding PermissionRequest would
  stall turns that never needed you, as with Cursor. Whether a held PermissionRequest blocks the TUI's own prompt or runs
  beside it is unknown.
- Questions are the `request_user_input` tool, answered in the TUI (Ctrl+Q opens them, Ctrl+X ignores one).
  `--disable-request-user-input` withholds it, and `--yolo` makes questions asynchronous. No hook reply for a question
  was found. A PreToolUse `updatedInput` on `request_user_input` might carry answers, as it does for Claude; untested.
- Session messages (`muse session-message send`) cannot answer: Muse treats a message from another session as data and
  never as your approval or input (docs).

## Reply, Pick up, New session

- **Reply:** an ordinary terminal composer (`❯`). Muse turns on bracketed paste and focus events at start
  (`ESC[?2004h`, `ESC[?1004h`), so a paste and Return should land as it does for Claude Code. Not driven.
  `session-message` is not a reply (above).
- **Pick up:** `muse resume <id>` (or the session's name) reopened the exact session with its history. It keeps the
  session's own folder in the log, but the TUI's footer showed the folder it was started from, so start it in the
  session's folder. `muse resume --last` takes the newest in the current folder. Resume takes no prompt, so words for a
  resumed session are typed after it opens. Driven.
- **New session:** `muse '<prompt>'` in the folder opened the TUI and sent the prompt (driven, trusted folder). In a
  folder Muse has not seen, a trust question comes first ("Do you trust this workspace?", Trust and continue or Quit).
  `--trust-workspace` skips it for one run without saving. Driven up to the question. Whether the prompt then goes out
  after you trust was not driven.
- The first run with no login asks you to sign in (browser or API key) before any of this (docs).

## Pull requests (not driven)

A shell call's result is in `tool_result_batch_committed`; output too big to keep inline goes to `tool-outputs/` in the
session folder (docs). The shell runs in Seatbelt with network through Muse's proxy by default, so `gh` should reach
GitHub. A `gh pr create` address should then be in the log, but none was seen.

## Open

- **Needs the owner:** a Meta login on this Mac, `muse login` (approve a code in the browser) or `META_API_KEY` from the
  Meta Model API dashboard. Then drive: a tool call and its records; an approval in Ask me mode with a logging
  PermissionRequest and Notification hook; a held PermissionRequest answered from a hook; a `request_user_input`
  question; a `gh pr create`; a real reply typed into the pane; whether the prompt goes out after the trust question.
- `~/Library/Application Support/Muse/session-name-authority/` now exists in the real home: Muse made it during the
  stand-in runs. It holds only names for those scratch sessions.
- Settings that fail validation make Muse refuse them (docs): `HookInstaller` must write valid JSON with
  `schema_version` and leave the rest untouched.
