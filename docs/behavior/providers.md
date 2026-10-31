# Providers: what Perch can do with each

A provider is anything Perch lists sessions from (an agent or an app) or follows a session into (a host). How each one works
is in [sessions.md](sessions.md), [agents.md](agents.md), [status.md](status.md) and [replies.md](replies.md); this page
is the summary to check before promising a feature, and the row a new provider fills in
([the skill](../../.claude/skills/add-provider/SKILL.md)).

## Agents and apps

✓ works · ~ partly (see the limits below) · ✗ not possible today · — does not apply

| Provider | Listed | Words and recap | Live status | Approvals from the notch | Questions from the notch | Reply | Pick up | New session | Pull requests |
|---|---|---|---|---|---|---|---|---|---|
| Claude Code, terminal | ✓ | ✓ | ✓ hooks | ✓ | ✓ | ✓ typed into its pane or tab | ✓ | ✓ | ✓ from its log |
| Claude Code, Claude app | ✓ | ✓ | ✓ hooks | ✓ | ✓ | ✓ through the app's window | ✓ link | ✓ link | ✓ the app's own list |
| Claude Code, cloud | ✓ | ✗ | ~ the app's cache | ✗ | ✗ | ✗ | ✓ in the browser | ✗ | ✗ |
| Claude tasks | ✓ | ~ | ~ the app's cache | ✗ read only | ✗ read only | ~ pasted | ✓ link | ✗ | ✗ |
| Claude chats (off by default) | ✓ | ~ | ✗ | — | — | ~ pasted | ✓ link | ✗ | — |
| Codex, terminal | ✓ | ✓ | ✓ hooks | ✗ | ✗ | ✓ typed into its pane or tab | ✓ | ✓ | ✓ from its log |
| Codex, Codex app | ✓ | ✓ | ✓ hooks | ✗ | ✗ | ~ pasted | ✓ link | ✓ link | ✓ from its log |
| OpenCode (1 and 2) | ✓ | ✓ | ✓ plugin | ✓ | ✓ | ✓ typed into its pane or tab | ✓ | ✓ | ✓ from its log |
| pi | ✓ | ✓ | ✓ extension | — no prompts | ✗ | ✓ typed into its pane or tab | ✓ | ✓ | ✓ from its log |
| Cursor, local chats | ✓ | ✓ | ✓ hooks | ✓ through its window | ✗ | ✓ through its window | ✓ link | ✗ | ✗ |
| Cursor, cloud agents | ✓ | ✗ | ~ its cache | ✗ | ✗ | ✗ | ~ link not driven | ✗ | ✗ |
| Muse, Dots, Grok Bot, Oh My Pi | design only | | | | | | | | |

## Hosts

| Host | Pick up | Reply | The session you are in |
|---|---|---|---|
| herdr | ✓ the pane | ✓ the pane | ✓ |
| tmux | ✓ the pane | ✓ `send-keys` | ✓ |
| cmux | ✓ the surface | ✓ AppleScript | ✓ |
| agterm | ✓ the pane | ✓ `agtermctl` | ✓ |
| Conductor | ✓ the workspace, through Accessibility | ~ pasted | ✓ |
| Terminal, iTerm2 | ✓ by tty | ✓ | ✓ |
| Warp | ✓ by its tab link (older Warp: tabs 1 to 9) | ✓ | ✓ |
| Ghostty | ~ by folder | ~ only when one terminal is in that folder | ~ |
| Any other terminal | ~ brought forward | ✗ copied | ✗ |

## Limits worth knowing

- **Claude Code.** Claude sends no hook for Stop or Esc, so the transcript wins there. In Bypass permissions mode questions need the extra PreToolUse hook, which blocks the app's own prompt while held.
- **Claude app replies** lean on its page internals (`ClaudeComposer`); an update can drop them to the paste fallback.
- **Claude tasks, chats and cloud sessions** come from the app's cache of claude.ai: words only for what was opened on this Mac, no hooks, approvals shown but not answerable. Read every 5 s, not watched.
- **Codex** runs its hook before its own prompt, so Perch can only show that it asks. Codex skips a new hook until you trust it once.
- **OpenCode** requests are held beside OpenCode's own prompt and never block it. OpenCode 2's questions are forms, answered through `opencode api`. OpenCode 1.3 and older are not reached by the plugin.
- **pi** has no permission prompts; its extension prompts are answered in the terminal.
- **Cursor** approvals are read from its database (about 15 s late) and pressed in its window; a request older than four hours is dropped. Its hooks that can allow or deny are not installed, since they fire for every command. No questions, no new session (its `prompt` link cannot name a folder), and its transcripts hold no tool results, so no pull requests.
- **Cloud agents** (Claude Code cloud, Cursor cloud) are a list only: no transcript on this Mac, no hooks.
- **Running detection** (`Agent.recognise`) knows Claude Code, Codex, OpenCode and pi; one Perch does not recognise never counts as running, so Pick up starts a second copy.

## Design only

Muse, Dots, Grok Bot and Oh My Pi are drawn in the design page (PR 137). Nothing in Swift reads them yet; their spikes in
`docs/spikes/` say what is possible.
