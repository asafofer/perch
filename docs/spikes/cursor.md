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
- **Not possible:** a new session in a chosen folder (the `prompt` link asks you to confirm, and cannot name a repository),
  answering approvals (below).

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

Perch installs `beforeSubmitPrompt`, `postToolUse`, `postToolUseFailure` and `stop` (flat entries, `"version": 1`).

## Approvals: not answered from the notch

Cursor can allow, deny or ask from `beforeShellExecution`, `beforeMCPExecution` and `preToolUse`. Those fire for every command,
including ones Cursor runs without asking (this Mac auto-runs: a `Shell` call ran with no prompt), so Perch cannot tell which
need an answer; holding them stalls the agent and answering them replaces Cursor's own prompt. Cursor's prompt itself could not be
exercised here, so its buttons were never read. Perch shows a call that waits (the transcript) and opens the chat.

## Accessibility

Cursor's window is Electron: `AXManualAccessibility` makes it expose a web area (`Cursor Agents`). The chat in front is the button
`Chat title. <title>`; the prompt is an `AXTextArea` ("Prompt", ProseMirror) and is focused after the chat link opens, so a paste
and Return reply works as it does for Codex. Pressing buttons by title (New Chat, Cancel) works through `AXPress`.

## Open

- A chat started in the classic editor window (not the Agents window) may not be found by the link ("We can't find this agent"); not seen on this Mac.
- The `agent` CLI keeps its sessions elsewhere (not found here; no CLI binary installed). Not read.
- A Cursor that predates the `composerHeaders` table: the folder then comes from the transcript folder's name.
