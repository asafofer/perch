# Spike: Grok Bot as a source

2026-10-31. Grok Bot 0.78.1 on this Mac, bundle id `com.anysphere.sand`, URL schemes `grokbot://` and `sand://` (the same
links also go through `https://cursor.com/grok-bot/link/v1/…`). Read from its files, its bundled code (`app.asar`, extracted
to a scratch folder) and its window's Accessibility tree. Nothing was clicked or typed, no link was opened, and nothing was
sent to it. Where a claim needs the running app it says "not driven".

## In short

Grok Bot is not a coding agent on this Mac. It is an Electron app (Electron 42, Anysphere's own "Dune" app framework, made by
the Cursor team, signed "SpaceXAI") in front of named bots that run in the cloud: each bot lives in a remote box
(`/home/box/sand-data/agents/<id>/store.db`) and talks to you in one long chat. A small daemon on the Mac runs local tools
for them (iMessage, Mail, phone, computer use) when you allow it. There is no folder, no transcript file, no hook and no CLI.
What Perch can read is the app's own cache of the bot list and of the recent chat of each bot, written while the app runs.

| Listed | Words and recap | Live status | Approvals | Questions | Reply | Pick up | New session | Pull requests |
|---|---|---|---|---|---|---|---|---|
| ✓ the app's cache | ~ last message always, the rest only for bots opened on this Mac | ~ the app's cache: needs you and unread, not working | ✗ read only | ✗ read only | ~ pasted, not driven | ~ link, not driven | ✗ | ✗ |

- **Listed ✓.** One row per bot from `roster.last-roster` (name, times, unread, `awaitingUserResponse`), rewritten 250 ms
  after each change while the app is open.
- **Words ~.** The roster's `lastEntry.text` is the newest message for every bot. Fuller words come from
  `transcript.replicas.<bot id>`, the latest entries the app keeps (about 200), with no tool calls and no turn end.
- **Live status ~.** "Needs you" from `awaitingUserResponse` and from pending cards in the cache (a question, an approval, a
  sign-in it handed you). "Done" only as unread. "Working" (`isRunning`) is live from the server and never written down.
- **Approvals and questions ✗, read only.** They show up in the cache, but the answer is an RPC from the app to the
  server with your account. No hook, no local socket, no file to write. Pressing the card's button in its window may work
  later, the same way Perch does for Cursor; not driven.
- **Reply ~.** `grokbot://app/v1/prompt?id=<bot id>&text=<words>` puts your words in that bot's composer (it does not send,
  and keeps a draft already there). Then Return through Accessibility, as for Codex and Cursor. Not driven.
- **Pick up ~.** `grokbot://app/v1/agent?id=<bot id>` opens the bot, `grokbot://app/v1/task?agent=<bot id>&id=<10 hex>` a task.
  Read from the link table; not driven.
- **New session ✗.** A bot has no folder. A new bot is made with the New Bot button; the prompt link without `id` only fills
  the main bot's composer.
- **Pull requests ✗.** No tool results are kept. The only pull request data is on Cursor cloud agents a bot starts
  (`cloud-agents.infos`: `prUrl`, `prState`, `prNumber`), which could become a ~ later.

Code it would need: a `GrokBot.swift` store in PerchCore (find the account's files in `sand-client-persistence`, decode the
base32 names, read the roster and replicas as JSON), a scanner in `SessionScan.swift` and `RealSessionProvider`, a `grokbot`
`Agent` (no resume command, no process, answers off), `Restorer.link` for the agent link, `AppIcons` for
`com.anysphere.sand`, a watch on the persistence folder, and for Reply a small window driver beside `CursorWindow.swift`
(prompt link, then Return). Status words come from the roster and the cache, not `LiveStatus` hooks.

## What it is

| | |
|---|---|
| App | `/Applications/Grok Bot.app`, Electron 42 (`AtomApplication`, `Electron Framework.framework`), `package.json` name `sand`, "Grok Bot desktop agent", homepage cursor.com, built 2026-10-28 |
| Bundle | `dist/electron-main` (main process), `dist/renderer` (React page), `dist/node-agent-coordinator`, `dist/local-exec-daemon`, native helpers (`sand-webauthn-signer`, `sand-op-launcher`). Dependencies are `@anysphere/*` (`grok-bot`, `grok-bot-harness`, `agent-transcript`, `local-exec`, `dune`, `messages-mac`, …) |
| Where agents run | In the cloud. Every bot in the list has `harness: "temporal"` and a `path` under `/home/box/sand-data/agents/<id>/`. No agent process runs on the Mac |
| On the Mac | The local-exec daemon dials out to the server and runs local tools for the bots (`~/.grokbot/local-exec-daemon.log`: "user-computer-watch … connected"). Local tool permission is a setting (`~/.grokbot/settings.json` `localToolPermission`, `always` here); computer use and Mac device tools have their own gates (both off here) |
| Computer use | `~/.grokbot/computer-use/Grok Bot Computer Use.app`, bundle id `co.anysphere.grok-bot-computer-use`, executable `CUGrokBotService`. Its logs are in `~/Library/Application Support/grok-bot-computer-use/` |
| CLI | None. No `grok`, `grokbot` or `sand` on the PATH, no CLI in the bundle |
| Hooks | None. Nothing in the bundle reads a hooks file; it writes nothing to `~/.claude` or `~/.cursor` here |

## Running (the process table)

| Process | argv[0] |
|---|---|
| The app | `/Applications/Grok Bot.app/Contents/MacOS/Grok Bot` |
| Renderer, GPU, network, audio | `…/Frameworks/Grok Bot Helper (Renderer).app/…` and `Grok Bot Helper.app/… --type=…` with `--user-data-dir=…/Application Support/Grok Bot` |
| Agent coordinator (supervisor) | `Grok Bot Helper --type=utility --utility-sub-type=node.mojom.NodeService`, pid in `~/.grokbot/local-exec-supervisor.json` |
| Local-exec daemon | the same helper line, pid in `~/.grokbot/local-exec-daemon.json` (`pid`, `startedAt`, `servingAt`, `inflightCount`) |

Neither helper listens on a port or a Unix socket (`lsof`: only TLS connections out, and Chromium's `SingletonSocket`).
There is one process set per app, not per bot, so `Agent.recognise` has nothing to match and running detection does not
apply. `~/Library/Application Support/Grok Bot/desktop-status.json` says whether the app is up and signed in (`pid`,
`appVersion`, `startedAtMs`, `signedIn`).

## Where the data is

All under `~/Library/Application Support/Grok Bot/sand-client-persistence/`. Each file is one JSON "slice",
`{"schemaVersion": n, "value": …}`, and its name is the slice key in lower-case base32 without padding, plus `.blob`.
Keys look like `sand.client.slice.account.<account, URL-encoded>.<slice>`, or `sand.client.slice.<slice>` for ones not tied
to an account. The current account is in `sand.client.slice.client-meta.account-slot` (`value` is the account id). The app
moved here from Local Storage on 2026-10-21 (`.migrated-from-local-storage`). Writes are debounced (roster 250 ms,
transcripts about 2 s) and happen only while the app runs; a bot that moves on while the app is closed shows once it
reopens and refetches.

Slices seen here: `roster.last-roster`, `transcript.replicas.<bot id>` (5), `cloud-agents.infos`, `selection.last-agent`,
`ui-agent-refs`, `sidebar.last-sections`, `send-journal` (messages still being sent), `weekly-usage.cache`, `ui-layout`
and a few settings. The app also knows `agent-tasks.last-thread-rows` and `composer-drafts` (not present here).

### The list: `roster.last-roster` (schema 4)

`value.rows`, one per bot (4 here, all `origin: user`, `visibility: owner`, `isGroup: false`):

| Field | Meaning |
|---|---|
| `id` | UUID, the bot id the links take |
| `name`, `title`, `description` | the bot's name (the row title), an empty title here, and a long description of what the bot is for |
| `createdAt`, `updatedAt`, `lastActivityAt`, `lastViewedAt`, `localActivityAt` | ms since 1970 |
| `lastEntry` | `{kind: "text", text, sessionPreview: {kind: "message_text", text}}`, the newest message |
| `lastMessageId`, `newestEntryId` | entry ids like `t57s1` (turn 57, step 1) |
| `hasUnread`, `unreadCount`, `unreadThreadCount` | what the sidebar dot shows |
| `awaitingUserResponse` | null, or `{reason, reasonCopy, since}` while the bot waits on you. `reason` is free text from the server. Null for every bot here, so the filled shape is from the code only |
| `isHiddenFromSidebar`, `isRemovedFromSidebar` | the nearest thing to archived |
| `isGroup`, `memberIds` | a room with several bots (a subagent-like case) |
| `harness`, `path`, `origin`, `visibility`, `teamId`, `published` | where it runs and who owns it |

No folder, no repository, no `isRunning`. In the code `isRunning`, `isRunningTurn` and `awaitingSessionIds` arrive live
from the server and are kept in memory only.

### The words: `transcript.replicas.<bot id>` (schema 1)

`value.entries` plus `epochHint`, `acceptedSequenceHint`, `persistedAt` and an `unreadAnchor`. One file per bot opened on
this Mac (all four here, and one for a bot no longer in the list). The cache is a window: one bot held 200 entries while its
newest `seq` was 602.

| Entry `kind` | What it holds |
|---|---|
| `message` | what you sent: `role: "user"`, `content`, `richText`, `isStreaming`, `timestampMs`, `clientNonce`; with `fromAgent`/`toAgent` when bots talk to each other |
| `send-message` | what the bot sent, by `message.type` (below) |
| `user-attachment` | a file you attached: `file_name`, `file_path`, size |
| `event` | `automation-changed` (`created`, `updated`, `deleted`, `disabled`) for its routines |

`send-message` types counted here: `text` 349, `widget` 32, `email-draft` 5, `attachment` 2, `cursor-agent` 2,
`secret-request` 1, `connector` 1. The code knows about 30 more, among them `local-tool-permission`,
`auto-review-approval`, `cookie-origin-approval`, `virtual-card-approval`, `publish-approval`, `connector-grant`,
`credential-request`, `user-form`, `slack-draft`, `imessage-draft`, `calendar-event`, `phone-call`.

Tool calls (`tool-call`), `notice` and `feedback` are entry kinds in the code but none were cached, and nothing marks the
end of a turn. So a recap can say what the bot last told you, not what it did.

### Waiting on you, from the cache

| Card | Pending when |
|---|---|
| `widget` (a question: `widget.prompt`, `widget.options[{label, value?, style?}]`, `allowCustom`) | neither `respondedValue` nor `widgetSkipped` is set. Here: 20 answered, 11 skipped, 1 open |
| `local-tool-permission` (`ask: {requestId, status, action, target, …}`; actions like `send-imessage`, `run-phone-tool`, `use-app`) | `ask.status` is `pending` (then `allowed`, `always`, `expired`) |
| other approvals (`…-approval`, `connector-grant`) | `approval.status` / `ask.status` is `pending` |
| a sign-in it hands you (`boxRequestId`, `boxReason: "auth"`, `boxInstruction`) | no `boxResolution` yet (`handed_back`, `dismissed` when done). 3 here |
| `secret-request` | no `secretProvided` |

None of the approval kinds appeared in this cache: local tools are set to `always` here, so nothing asked.

### Cursor cloud agents it starts

A `cursor-agent` card (`bcId`, `title`) is a Cursor cloud agent a bot started. `cloud-agents.infos` keeps one entry per
`bcId`: `status` (`finished`), `name`, `branchName`, `prUrl`, `prState`, `prNumber`, `mergeableState`, `lastActivityAtMs`,
`filesChanged`, lines added and removed. One entry here, no pull request.

## Links (from the link table in `main-core.cjs`)

Authority `app`, schemes `grokbot` and `sand`, at most 2048 characters, routes under `/v1/`:

| Route | Parameters | What the page does with it |
|---|---|---|
| `agent` | `id` (bot id) | opens that bot |
| `thread`, `task` | `agent` (optional), `id` (10 hex) | opens that task of the bot |
| `prompt` | `text` (up to 1000), `id` (optional bot id) | puts `text` in that bot's composer, or the main bot's without `id`. Keeps a non-empty draft instead (`kept-draft`). Never sends |
| `settings` | `id` (a settings page, e.g. `always-ask-rules`, `allow-without-asking-rules`, `computer-use`) | opens Settings there |
| `sidebar` | `agent`, `tab`, `automation`, `target` | opens a bot's side panel |
| others | | `open`, `messages`, `referral`, `create-team-bot`, `bot-template`, `marketplace`, `plugin/add`, `plugin/native`, `vault`, `agent-invite`, and OAuth callbacks |

So Pick up is `grokbot://app/v1/agent?id=<roster id>`. Not opened in this spike.

## Accessibility (read only)

The window is Electron's: without `AXManualAccessibility` it shows only the title bar buttons. With it set (as Perch does for
Cursor; left on), the window exposes a web area `Grok Bot` with:

- the sidebar as an `AXList` of `AXButton`s named after each bot (`<name>, Unread activity` when it has unread, `Grok Bot,
  Main Bot` for the main one), plus `New Bot` and `Connect apps`;
- an `AXHeading` with the open bot's name and `View conversation details`;
- the composer, an `AXTextArea` named `Prompt`, with `Composer actions`, `Start voice input` and `Start voice chat`.

So a reply by prompt link, then Return in `Prompt`, looks possible, and so does reading which bot is in front from the
heading. Neither was driven. Approval and question cards were not on screen, so their buttons were not seen.

## Not driven

- Any link: opening a bot, prefilling the composer, what happens when the app is closed (Cursor dropped a link sent during
  start-up).
- Reply end to end, and pressing a question's option or an approval's button in the window.
- A filled `awaitingUserResponse` in the roster, and a pending `local-tool-permission` in the cache (local tools are set to
  `always` here).
- Tasks and threads (`agent-tasks.last-thread-rows` is not present here) and rooms with several bots.

## Open

1. **Should it be on by default?** These bots read and draft email, iMessage, X posts and calendar events. Like Claude
   chats, their words can be personal and are not coding work. Off by default, or a tile that shows only a count, may fit
   better.
2. **Is a bot a session?** A bot is one endless chat, not a task with an end. A row per bot, titled by its name and showing
   its last message, fits the list; "done" can only mean "it said something you have not read".
3. **Fragility.** The slice names, base32 file names and entry shapes are the app's internals (schema 4 for the roster).
   A change would make the rows quietly disappear, as with the Claude chats cache.
