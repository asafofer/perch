# Spike: Cursor as a source

2026-10-24, issue #105. Cursor 3.23.12 on this Mac, bundle id `com.todesktop.230313mzl4w4u92`, URL scheme `cursor://`.
Everything below was checked against the running app unless it says otherwise. What shipped is in
[sessions.md](../behavior/sessions.md) and [status.md](../behavior/status.md).

## In short

- **Reading chats works well.** Plain JSONL transcripts hold what was said; Cursor's database holds titles and folders.
- **Pick up reaches the exact chat.** `cursor://anysphere.cursor-deeplink/agent?id=<chat id>` is not documented (the docs list only
  `prompt`, `command` and `rule`), but the Agents window handles it (`handleAgentOpen` → `glass.openCloudAgentById`, found in
  `workbench.glass.main.js`) and opens any local chat by its id, with the cursor in its prompt. Tried on a chat with a folder and one without.
- **Live status works through hooks** (`~/.cursor/hooks.json`), as documented.
- **Approvals can be answered, through Cursor's window** (below), not through its hooks.
- **Not possible:** a new session in a chosen folder (the `prompt` link asks you to confirm, and cannot name a repository).

## Where the data is

| | |
|---|---|
| Transcripts | `~/.cursor/projects/<folder>/agent-transcripts/<id>/<id>.jsonl`. `<id>` is the chat's `composerId` and the hooks' `conversation_id`. Folder: the path with every symbol a dash, dots dropped (`…/token/.claude/worktrees/x` is `…token-claude-worktrees-x`), or `empty-window` |
| Lines | `{"role":"user\|assistant","message":{"content":[{"type":"text","text":…}\|{"type":"tool_use","name":…,"input":…}]}}` and `{"type":"turn_ended","status":"success"}`. No times, no tool results, no folder. A user line is `<timestamp>…</timestamp>\n<user_query>…</user_query>`; replies end in `[REDACTED]` |
| Tools seen | `Shell` (`command`, `description`), `Read`, `Grep`, `Glob`, `GetDynamicTools` |
| Database | `Application Support/Cursor/User/globalStorage/state.vscdb`, SQLite in WAL mode (5.8 MB here, several GB on busy installs). `composerHeaders` (`composerId`, `workspaceId`, `isArchived`, `isSubagent`, `lastUpdatedAt` mostly null, a `value` JSON), `cursorDiskKV` with `composerData:<id>` (`name`, `status`, `createdAt`, `workspaceIdentifier`, `hasUnreadMessages`, and the chat's encryption keys), `bubbleId:…` (older chats' messages, not read) |
| Folder of a window | `User/workspaceStorage/<workspaceId>/workspace.json`: `{"folder":"file:///…"}` |
| Subagents | `isSubagent` in the header |

Cursor rewrites a transcript when you open its chat: a turn it finds open is closed with
`{"type":"turn_ended","status":"error","error":"User aborted request"}`, so opening a chat moves its file's time.

## Hooks (live, from a logging hook in `~/.cursor/hooks.json`)

One prompt in a new chat produced, in order: `sessionStart`, `beforeSubmitPrompt`, `afterAgentResponse`, `stop`. Every payload has
`conversation_id` (= `session_id`), `generation_id` (empty at `sessionStart`), `model`, `composer_mode`, `workspace_roots` (empty for
a chat with no folder), `user_email`, `cursor_version` and `transcript_path` (null until the first reply). `afterAgentResponse` carries
`text` and token counts; `stop` carries `status` (`completed`) and `loop_count`. `beforeSubmitPrompt` has to be answered with
`{"continue":true}`. The hook runs in the Agents window as well as the editor.

Perch installs `beforeSubmitPrompt`, `postToolUse`, `postToolUseFailure` and `stop` (flat entries, `"version": 1`); with them installed, a real prompt in Cursor reached Perch as `cursor <id> started` and `finished`. Cursor also runs the Claude Code hooks of `~/.claude/settings.json` for its chats, so the same turn arrives a second time as `claude`.

## Approvals

Cursor can allow, deny or ask from `beforeShellExecution`, `beforeMCPExecution` and `preToolUse`. Those fire for every command,
including ones Cursor runs without asking (this Mac auto-runs: a `Shell` call ran with no prompt), so Perch cannot tell which
need an answer; holding them stalls the agent and answering them replaces Cursor's own prompt. Cursor's prompt itself could not be
exercised at first; later a web search did ask. The header (`composerHeaders.value`) then said `hasBlockingPendingActions: true` (about 15 s after the prompt showed), the newest bubble's `toolFormerData` was `{name: web_search, status: loading, params: {searchTerm}}` (a command is `run_terminal_command_v2` with `params.command`), and the prompt's buttons were `AXButton` titled `Skip`, `Always Run` and `Run ⏎`. Perch reads that and presses `Run ⏎` or `Skip` after opening the chat by its link; tried both ways in the running app (Allow: the search completed; Deny: Cursor said it was skipped). A transcript never shows the pending call (no tool_use is written before it runs).

## Accessibility

Cursor's window is Electron: `AXManualAccessibility` makes it expose a web area (`Cursor Agents`). The chat in front is the button
`Chat title. <title>`; the prompt is an `AXTextArea` ("Prompt", ProseMirror) and is focused after the chat link opens, so a paste
and Return reply works as it does for Codex. Pressing buttons by title (New Chat, Cancel) works through `AXPress`.

Cold start (found by trying it, Cursor quit, then Reply from the card):
- A link that arrives while Cursor is still starting is dropped: Cursor comes up on a new-chat page. So Perch sends it again once the Agents window is readable (`CursorWindow.open`).
- The Agents window is not the focused window until Cursor is in front: it is found by its title in `AXWindows`, not by `AXFocusedWindow`.
- `AXManualAccessibility` set before the window exists builds no tree: the web area only shows after it is set again, so Perch asks again every few seconds while there is none (`enableAccessibility`) and waits up to 24 s. It took about 5 s to read the chat after a start.

## Tried since, all in the running Perch

- A chat started in the classic editor window (`Cursor` window with a folder, its own agent panel): it has a transcript under the folder's name, a header with that window's workspace id, hooks fire, Perch lists it with the folder's name, and the link opens it in the Agents window (which lists the editor's chats under their repository).
- Perch off: Cursor's prompts go through unchanged (the hook script still prints `{"continue":true}`).
- Settings, Live status on and off, against a stand-in home (`PERCH_HOME`): four entries in `.cursor/hooks.json` and the other agents' hooks and plugins; off leaves `{"version": 1}`.
- A 2.9 GB database made for the purpose (700 000 rows): the header and `composerData` lookups by key took under a millisecond.

## Open

- The `agent` CLI keeps its sessions elsewhere (not found here; no CLI binary installed). Not read.
- A Cursor that predates the `composerHeaders` table: tested with a fixture only (`aCursorWithoutTheHeadersTableStillListsItsChats`); the folder then comes from the chat's own `workspaceIdentifier`, else the transcript folder's name.
