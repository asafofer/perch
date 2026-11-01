# Spike: Oh My Pi (omp) as a provider

2026-10-31. omp 18.14.1 (github.com/can1357/oh-my-pi, a fork of pi), installed with Homebrew (`brew install can1357/tap/omp`,
one 215 MB binary at `/opt/homebrew/Cellar/omp/18.14.1/bin/omp`). A terminal agent: no app, no bundle id, no URL scheme that
opens a session. Everything below was driven against the real omp in a stand-in home (`HOME=<scratch>/home`), inside a
private tmux server. No model key or login is set up for omp on this Mac (pi's logins live in `~/.pi/agent/auth.json`, which
omp does not read), so omp talked to a small local stand-in for a model: an OpenAI-style endpoint on 127.0.0.1 declared in
the stand-in home's `~/.omp/agent/models.yml`, which answers each prompt with a fixed reply or tool call. omp itself, its
files, its prompts and its extensions were all real.

## In short

- **The likely win holds, mostly.** omp writes pi's session format (same `message` entries, `toolCall` blocks, `toolResult`,
  `stopReason`) under `~/.omp/agent/sessions/`, and loads pi-style extensions (`export default function (pi) { pi.on(…) }`)
  from `~/.omp/agent/extensions/`. `PiTranscript.digest` reads an omp file's words unchanged.
- **Three differences break pi's code as it is.** The file's first line is a 256-byte title slot, not the header, so
  `SessionScanner.head` (first line only) finds no id and lists nothing. Titles come from that slot and `title_change`, not
  `session_info`. omp has no `agent_settled`, so pi's extension never says Stop.
- **pi's Perch extension does not load in omp** (`~/.pi/agent/extensions` is not one of omp's folders), so nothing reports
  twice. A copy in omp's folder loads and reports start and tools.
- **omp asks.** It has tool approvals (off by default: `tools.approvalMode` is `yolo`) and an `ask` tool for questions. An
  extension sees both. A question can be answered from outside; an approval cannot, except by keys in its terminal.

| Provider | Listed | Words and recap | Live status | Approvals from the notch | Questions from the notch | Reply | Pick up | New session | Pull requests |
|---|---|---|---|---|---|---|---|---|---|
| Oh My Pi | ✓ | ✓ | ✓ extension | ~ shown, answered in its terminal | ✓ the extension stands in for `ask` | ✓ typed into its pane or tab | ✓ | ✓ | ✓ from its log |

Limits behind the row:

- **Approvals.** The extension hears `tool_approval_requested` and `tool_approval_resolved`, but no extension call answers
  one: omp asks its own UI. The card can show what is asked; Allow and Deny would have to be keys sent into the pane
  (Enter or Ctrl+Enter allows, Esc denies), which Perch does for no agent today. With the default mode nothing asks.
- **Questions** were answered from outside with a test extension and a file standing in for Perch's socket, not through
  Perch itself.

## Code it would need

Most of pi's code is reused; omp is a second pi with its own folder.

| Piece | Change |
|---|---|
| `Agent.swift` | `Agent.omp`: id `omp`, name "Oh My Pi", short "omp", resume `omp --resume`. `recognise`: an executable named `omp`; `mayBe` takes `omp`. `answersFromNotch` covers allow, deny and questions alike, and omp answers only questions, so the flag needs splitting or a per-kind check in `Ask.answerable` |
| `Pi.swift` | `PiTranscript.digest` as it is, plus the title: the `title` line's `title` and the newest `title_change`'s `title` (an empty slot means none). `firstPrompt` as it is |
| `SessionScan.swift` | `pi()` taking the root (`.omp/agent/sessions`) and the agent, and a head read that skips a first `title` line. Subagent and advisor transcripts sit one folder deeper (`<bucket>/<session>/<AgentId>.jsonl`), so the one-level scan already leaves them out |
| `NotchController` watch paths | add `.omp/agent/sessions` |
| `PerchPlugins` | an `omp` body: pi's, posting to `/omp/<event>`, with the changes below |
| `HookServer`, `HookInstaller` | `omp` in `agents`; its file `~/.omp/agent/extensions/perch.ts` |
| `LiveStatus` | omp's tool names (`bash`, `read`, `edit`, `ask`) for the card's step |
| `NewSession`, `Terminals` | the command `omp '<words>'` in the folder; resume and reply as pi |
| `PullRequestScan` | nothing: pi's `toolCallId` already matches |
| Icon | omp.sh's mark in `MARKS` (no app) |

The extension, against pi's:

- Stop on `agent_end` (or `session_stop`, which carries `last_assistant_message` and `session_id`) in place of `agent_settled`.
- Drop `ui_prompt_start` and `ui_prompt_end` (not in omp).
- Leave out subagents: omp runs every extension in each subagent session too, so check `ctx.agent.kind === "main"`.
- Approvals: keep each `tool_call`'s input by `toolCallId`; on `tool_approval_requested` post PermissionRequest with it, on
  `tool_approval_resolved` let it go.
- Questions: register a tool named `ask` that runs omp's own through `ctx.invokeTool` and holds a request to Perch at the
  same time, as the OpenCode plugin's `hold` does. Whichever answers first wins; the other is aborted.

## Where the data is

| | |
|---|---|
| Sessions | `~/.omp/agent/sessions/<bucket>/<time>_<id>.jsonl`. The bucket is the folder with `/` as `-`: `-<path>` under home, `-tmp-<path>` under the temp folder, `--<path>--` elsewhere (pi always uses `--<path>--`). The folder itself is in the header. Profiles (`omp --profile x`) live in `~/.omp/profiles/<x>/agent/sessions`, not driven |
| Line 1 | `{"type":"title","v":1,"title":"Hello from the stub","source":"auto","updatedAt":…,"pad":"   …"}`, padded to 256 bytes and rewritten in place on a rename (the file keeps its size) |
| Line 2 | `{"type":"session","version":3,"id":"01a1921c-2bbb-71dc-9509-6b40e959ce31","timestamp":…,"cwd":…}`. Ids are UUIDv7 |
| Entries | `message` (roles `user`, `assistant`, `toolResult`), `model_change`, `thinking_level_change`, `title_change` (`title`, `source` `auto` or `user`), `custom` (`system-prompt-digest`, `tool_execution_start` with the call's args, `session_exit` when the process ends), `compaction`, `branch_summary` and others. Each has `id` and `parentId` (a tree, as pi), and a `runtime` version |
| Titles | Made by a model after the first turn (`source: auto`), or `/rename` (`source: user`) |
| Other files | `~/.omp/agent/agent.db` (credentials and settings, SQLite; not read), `models.yml`, `config.yml`, `logs/omp.<date>.<pid>.log`, `run/session-owners/<id>.lock` |

## Words

A turn as written (one line each, trimmed):

```
message user       [{"type":"text","text":"RUN in a new folder"}]
custom  system-prompt-digest
message assistant  stopReason toolUse  [{"type":"toolCall","id":"call_b9b3fa5a","name":"bash","arguments":{"command":"ls"}}]
custom  tool_execution_start  {"toolCallId":"call_b9b3fa5a","toolName":"bash","args":{"command":"ls"}}
message toolResult {"toolCallId":"call_b9b3fa5a","toolName":"bash","content":[{"type":"text","text":"Tool call denied by user: bash"}]}
message assistant  stopReason stop     [{"type":"text","text":"Listed the folder."}]
```

Run through PerchCore's own code (compiled with a small check, not the app), every omp file gave the right id, last prompt,
last reply and turn state from `PiTranscript.digest`; the title came out nil, and `SessionScanner.pi` pointed at omp's files
listed none, because `head` read only the title line.

## Status (a test extension logging every event to a file)

One prompt with a tool call, in order: `input`, `agent_start`, `turn_start`, `message_end` (user), `tool_call` (with input),
`message_end` (assistant, `stopReason: toolUse`), `tool_execution_start` (with args), `tool_approval_requested` (only when it
asks), `tool_approval_resolved` (`approved`, `reason`), `tool_execution_end`, `message_end` (toolResult), `turn_end`,
`turn_start`, `message_end` (assistant, `stop`), `turn_end`, `session_stop`, `agent_end` (`willContinue`). `session_start`
and `session_shutdown` bound the process. `agent_settled`, `ui_prompt_start` and `ui_prompt_end` never fired.

pi's Perch extension, copied into `~/.omp/agent/extensions/` with its post sent to a file: it loaded, and
`ctx.sessionManager.getSessionId()` gave the session's id, so it posted `UserPromptSubmit` and `PostToolUse` (`bash`, `ask`)
with the right id and pid, and never `Stop`. The same file in the stand-in's `~/.pi/agent/extensions/` did not load.

omp does not run Claude Code's command hooks from `~/.claude/settings.json` (it reads only `.claude/hooks/pre|post` script
files), so unlike Cursor a turn does not also arrive as `claude`.

## Approvals and questions

- **Approvals.** Started with `--approval-mode always-ask`, `ls` asked in a box above the composer: "Allow tool: bash",
  `Command: ls`, Approve, Approve bash for this session, Deny. Enter (sent with tmux) approved it and the tool ran; Esc denied
  it; typing a message denied it and steered the turn with that message ("type to deny and steer"). The transcript shows the
  call and its `tool_execution_start` with no result while it waits. `tool_approval_requested` carries `sessionId`,
  `toolName`, `toolCallId`, `approvalMode` and an optional `reason`, not the input; the `tool_call` before it has the input.
  The extension API has no way to answer: the prompt goes to omp's own UI (`requestApproval` in its `wrapper.ts`), and a
  `tool_call` handler can only block a call, not approve one past the gate. Modes: `yolo` (default, never asks), `write`,
  `always-ask`, `always-ask-cached`; folders in `tools.restrictedFolders` always ask.
- **Questions.** The model's `ask` tool showed a picker ("Which colour?", Red, Blue, Other). The extension sees it as
  `tool_call` and `tool_execution_start` with `{questions:[{id, question, options:[{label}], multi?, recommended?}]}`, and its
  end as `tool_execution_end`. An extension may register a tool with a built-in's name and run the original through
  `ctx.invokeTool`. A test extension did that for `ask` and raced omp's picker against an answer file: writing "Red" to the
  file closed omp's picker and the model got `User selected: Red`; answered in the terminal instead, the picker's answer
  went through as usual. A resumed session then shows that call as a plain tool line rather than omp's own question card.
- Holding the request does not block omp's prompt: the picker stays live beside it.

## Reply

Typed into its pane: text then Enter (tmux `send-keys -l`, then `Enter`) is sent as the next prompt, as with pi. A reply
typed while an approval waits denies it (above).

## Pick up

`omp --resume <id>` opens the exact session; an id prefix works (`01a1921c-2bbb`). Started from `/tmp`, it moved the process
to the session's folder. `omp --resume <id> '<words>'` resumed it and sent the words as the next prompt, in the same file.
Other forms: `omp -c` (the folder's latest), `omp --resume` (a picker), `omp --resume <path.jsonl>`.

## Running

```
  PID COMM ARGS
29655 omp  omp --model stub/stub --approval-mode always-ask
```

The executable is the binary itself (`lsof` txt: `/opt/homebrew/Cellar/omp/18.14.1/bin/omp`), argv[0] `omp`. omp is a
compiled Bun program, so inside it `process.argv` reads `bun /$bunfs/root/omp-darwin-arm64 …`, but the process table shows
`omp`. No helper process stayed running. `Agent.recognise` returns nil for it today. Not driven: the Bun global install
(`bun install -g @oh-my-pi/pi-coding-agent`, which needs Bun 1.4.4; this Mac has 1.3.13) and the curl installer.

## New session

`omp '<words>'` started in a new folder opened the TUI and ran the words as the first prompt at once; the session's file
went under that folder's bucket. `--cwd <folder>` also exists.

## Pull requests

With a stand-in `gh` on the PATH that prints an address, the model's `gh pr create --fill` call and its result were written
as pi's are (`toolCall` with `id`, `toolResult` with `toolCallId` and the address in its text). `PullRequestScan.created`
found `https://github.com/example/repo/pull/43` in that file, and did not take an address merely echoed by another command.
omp also reads GitHub itself (`pr://` paths in its `read` tool); those are not pull requests it opened.

## Open

- A real model was not used. Auto titles were seen (made by the stand-in's reply), interrupting a turn (Esc while working)
  and a failed request were not: the stand-in answers at once. Trying them needs `omp login` or a key in the owner's own omp.
- Subagents (`task`) were not run; their files sit in a folder per session, and the extension must skip their events.
- omp's docs say a turn only appends, but some of its commands (`/delete`, discarding a branch) can rewrite earlier
  records. Compaction and those were not driven.
