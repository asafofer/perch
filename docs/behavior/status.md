# Status: hooks, the transcript, background work

## Two sources

- With live status on, hooks say exactly what happened (`LiveStatus.apply`) and win over the transcript, except a stop: Claude sends no hook for Stop or Esc, so a transcript that ends in one after the last hook wins (`LiveStatus.holds`).
- Without hooks, status is guessed from the transcript's shape (`Recap.statusAndNext`).
- herdr's own reading of a pane counts between the two ([agents.md](agents.md)).

## Answering from the notch, per agent

- Claude's PermissionRequest hook runs alongside the app's own prompt, and whichever answers first wins, so Perch can allow, deny or answer a question (`answers` in `updatedInput`).
- In Bypass permissions mode Claude sends no PermissionRequest for a question, so Perch also installs a PreToolUse hook on `AskUserQuestion` (`Ask.viaPreToolUse`, tested against a real `claude` with a temporary settings file: allow plus `updatedInput.answers` is taken as the answer). That hook blocks the app's own prompt until it returns, so it is held only for a Claude app session you are not in, for the notch's nine seconds plus the question time, and let go the moment you are in that session (`HookServer.keepHolding`). `HookInstaller.upgrade()` adds it to an earlier install at launch.
- Codex's hook runs before its prompt, so Perch answers Codex at once with no decision and only shows the status.
- Perch's OpenCode plugin never blocks OpenCode: a permission or question is held open beside OpenCode's own prompt, an answer from the notch goes back through OpenCode's client, and one given in OpenCode makes the plugin drop its request.
- pi has no permission prompts. Its extension reports turns, tools, stops and extension prompts (pi 1.0+, answered in the terminal).

## Background work

- A turn can end while work it left in the background is still out: helpers (the Agent tool run in the background), a watch (Monitor), a command run in the background or moved there when it ran long. Claude Code tells the agent with a task notification when each ends and the agent carries on, so until then the session is at work, not done, whatever the Stop hook said (`SessionDigest.background`, `Project.waiting`). The Now row says what it waits on (`Background.step`).
- The transcript has it all: the launch in the tool result's `toolUseResult` (`isAsync` and `agentId`, `backgroundTaskId`, a Monitor's `taskId`), the end in a `queue-operation` holding `<task-notification>` with a `<status>`. A watch's events have none, and a helper that stopped with work of its own still out says it "is waiting on its own background work" and reports again at the end.
- A command that never ends by itself (a dev server, `tail -f`) does not count (`Background.neverEnds`).
- Work gone without a word (the app quit) stops counting after half an hour with no sign of life (`Background.out`): a helper's sign is its own transcript, `<id>/subagents/agent-<agentId>.jsonl` (`SessionScanner.heardFrom`), a command's its start, a watch's its own deadline.
- Helpers send their hooks with the session's id and their own `agent_id`: a helper's tool call settles only what that helper asked, never the question the session itself asks (`LiveStatus.apply`).

## Trying it

- Test the socket without touching any config: `echo '{"session_id":"…","tool_name":"Bash","tool_input":{"command":"ls"}}' | ~/.config/perch/hook claude PermissionRequest` (it waits for your answer on the card).
- Post test questions this way, to an idle session: a message sent in a Claude session while its question is open dismisses the question.
