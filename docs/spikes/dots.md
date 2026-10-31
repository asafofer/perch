# Spike: Dots as a source

2026-10-31. Dots live inside the ChatGPT app: `/Applications/Codex.app` 26.930.31730, shown as "ChatGPT" (its executable is
`ChatGPT`, its alternate name `Codex`), bundle id `com.openai.codex`, URL scheme `codex://` (it also takes `http` and `https`
links). This is the same app Perch already lists as the Codex app. Read from its files, its bundled code (`app.asar`,
extracted to a scratch folder) and OpenAI's docs and launch coverage. Nothing was clicked or typed, no link was opened, and
nothing was sent to it. Where a claim needs the running app it says "not driven".

## In short

A dot is an always-on agent that runs in OpenAI's cloud, on a computer of its own. On this Mac there is no process, no
transcript, no hook and no CLI for it. You talk to it in one long chat (a messaging room) in the ChatGPT app, on the web,
on the phone, in Slack or Teams. What Perch can read is the app's own saved copy of the dot's profile, kept in
`~/.codex/.codex-global-state.json` and written only while the app shows Dots.

| Listed | Words and recap | Live status | Approvals | Questions | Reply | Pick up | New session | Pull requests |
|---|---|---|---|---|---|---|---|---|
| ~ the app's cache, one row per dot | ~ last message preview only | ~ paused and unread, not working | ✗ read only, and not in the cache | ✗ same | ~ pasted, not driven | ~ `codex://dots`, not driven | ✗ | ✗ |

- **Listed ~.** One row per dot from `cloud-aeon-sidebar-cache-v1` and `primary-aeon-selection-v1`: name, status, paused,
  created, last check-in. Only as fresh as the app's last look: here the list was saved on 2026-10-06 and the primary dot on
  2026-10-14, though the app runs today.
- **Words ~.** The room's `message_preview` (the newest message, cut at 100 characters, and its time). No transcript, no
  tool calls, no turn end. The dot's tasks are on the server; the cache only holds its hidden heartbeat threads.
- **Live status ~.** `is_paused`, `status` (`active`, `deleting`), and unread (newest message after `last_read_at`).
  "Working" and "using the computer" come only from a live server stream and are never written down.
- **Approvals and questions ✗.** A dot asks inside its chat ("elicitations": allow, decline, allow for this conversation,
  always allow, forms, app sign-ins). Nothing of it reaches a local file, and the answer is a request to ChatGPT's server
  with your account. Pressing the button in the app's window may work later, as Perch does for Cursor; not driven.
- **Reply ~.** `codex://dots` opens the Dots page, then paste and Return into its composer through Accessibility, as for the
  Codex app. Not driven.
- **Pick up ~.** `codex://dots` (exactly that, no id) opens the Dots home. With one dot per account that is the dot; there is
  no link to a given dot or task. Not driven.
- **New session ✗.** No link carries words to a dot (`codex://dots` takes no prompt; `codex://threads/new?prompt=` starts a
  Codex task, not a dot message). A dot has no folder.
- **Pull requests ✗.** No log on this Mac. Cloud threads in the cache have no turns and no git info.

Code it would need: a `Dots.swift` store in PerchCore (read `electron-persisted-atom-state` from the global state file,
take the two keys, collapse `profilesByThreadId` by profile `id`, read times as ISO dates with six fractional digits), a
scanner in `SessionScan.swift` and `RealSessionProvider`, a `dots` `Agent` (no resume command, no process, answers off),
`Restorer.link` for `codex://dots` opened with the newest copy of the app (see Two copies), and the ChatGPT app's own icon
in place of the `MARKS.dots` ring (the design page says Dots is not installed; it is, inside ChatGPT).

## Where the data is

| | |
|---|---|
| File | `~/.codex/.codex-global-state.json` (847 KB here, plain JSON, rewritten often while the app runs). Under `electron-persisted-atom-state` (667 keys) |
| `primary-aeon-selection-v1` | `{accountId, userId, response: {selection, profile}}`. `selection`: `thread_id`, `generation`, `selected_at`, `aeon_id`, `available`, `messaging_room_id`. Saved after each fetch of the primary dot, and cleared when the server says none is available |
| `cloud-aeon-sidebar-cache-v1` | `{accountId, userId, hostId: "durable", revision, refreshStartedAtMs, profilesByThreadId, attachments, threads}`. Saved by the sidebar's `cloud-aeon-sidebar-threads` query (stale after 1 minute, refetched on mount, window focus and reconnect, behind a feature gate) |
| A profile | `id` (the aeon id, 69 characters), `display_name`, `color`, `avatar_manifest` (shape, eyes, colour), `messaging_room_id`, `active_root_thread_id`, `status`, `is_paused`, `isSafetyFlagged`, `safety_flag`, `aeon_kind` (`orbit`), `last_check_in_at`, `created_at`, `updated_at`, `messaging_room_preview` |
| `messaging_room_preview` | `id`, `name`, `type` (`DM`), `app_source` (`chatgpt:messaging`), `members` (role, name), `message_preview: {latest_item_timestamp, preview}`, `last_read_at`, `pinned`, `user_room_settings.notification_setting` |
| `threads` | Codex thread summaries: `id`, `name`, `threadSource` (`aeon` for the dot itself, `dreaming` for its heartbeat runs, `subagent`), `originator` (`orbit_cca`, `orbit_cca_web`), `source: {custom: "codex-cloud-agent"}`, `cwd` (`/workspace/scratch/…`, the dot's cloud computer), `status: notLoaded`, `turns: []` |
| `attachments` | `thread_id`, `parent_thread_id`, `attached_at`, `is_user_visible` (false for every one here) |
| `aeon-appearance-v2:<thread id>` | The avatar's colour, per root thread |

Here: one dot. The sidebar cache holds 6 entries in `profilesByThreadId`, all the same profile (the dot's root thread, its
heartbeat threads and one subagent), so a reader must collapse them by profile `id`. Between the two saves the dot's
`active_root_thread_id` changed and `is_paused` went from true to false, so the newer of the two wins.

Not used: the ChatGPT backend (`/cloud-aeons/primary`, `/messaging/rooms/{room_id}/messages`, `…/live` for the live stream,
`…/elicitation/response` for answers), which needs the token in `~/.codex/auth.json`. Perch should never touch that.

Looked at and empty of Dots: `~/.codex/state_5.sqlite` (local Codex threads; none from a dot, none with
`attached_thread_parent_id`), the app's Local Storage (`codex.chatgpt-conversations`, an old ChatGPT chat list from August),
and its IndexedDB (empty). The built-in browser's `chatgpt.com` storage is from July.

## Status, approvals and questions

From the bundled code and its strings (codename "orbit", the dot is an "aeon"):

- A dot's profile says Active ("working, waiting on subtasks, or active lately"), Paused, or No recent activity. A task in it
  is Working, Thinking or done. The live state (`turn_status: in_progress`, `computer_status: using_computer`) arrives over
  `POST /messaging/rooms/{room_id}/live` as a server-sent stream, and over a websocket. None of it is saved.
- Approvals and questions are elicitations on a message in the room: tool approvals with full parameters (Allowed, Declined,
  Allowed for this conversation, Always allowed), `form_elicitation`, app sign-ins and location. A web page
  (`elicitation.page`) answers one opened from Slack or Teams.
- A safety monitor can pause a dot ("paused out of precaution"); the profile then carries `isSafetyFlagged` and
  `safety_flag`. That is in the cache and could read as "needs you".

OpenAI's docs (help center, launch coverage, not driven): a dot "comes with strong defaults for which actions need your
approval", auto-review checks some actions first, and Custom Rules add limits. It works from its own cloud computer and,
with permission, on your Mac. No developer API was found.

## Links

The app's link handler (`bootstrap` in `app.asar`):

| Link | Opens |
|---|---|
| `codex://dots` | the Dots home (only this exact form) |
| `codex://orbit` | dot onboarding |
| `https://chatgpt.com/codex/open-app?target=dots` | the same as `codex://dots` |
| `codex://threads/<id>?hostId=<host>` | a Codex thread. Whether a dot's thread (`hostId=durable`) opens this way: not driven |

Inside the app a dot lives at `/dots/<conversationId>` (also `/dots/home`, `/dots/new`, `/o/<id>`), but no link reaches
those routes.

## Two copies

`/Applications/ChatGPT.app` (26.707.62119, July) and `/Applications/Codex.app` (26.930.31730, running) share the bundle id
`com.openai.codex` and both claim `codex://`. The older one has no Dots code. A link opened by scheme may land in the
wrong copy, so Perch should open it with the newest copy's URL. Perch's Codex links have the same exposure today.

## Running

No process: a dot runs in the cloud. The app is `/Applications/Codex.app/Contents/MacOS/ChatGPT`. Whether this Mac is
connected as the dot's computer (Settings, "Allow access"), and what a task it runs here looks like, was not driven; the
strings say it shows as "Environment: This computer", so it may arrive as an ordinary Codex thread.

## Open

- **Freshness.** Both saves are weeks old while the app runs. To check whether opening Dots refreshes them, the owner
  opens ChatGPT (`/Applications/Codex.app`), clicks the dot in the sidebar and waits for its messages, then
  `refreshStartedAtMs` under `cloud-aeon-sidebar-cache-v1` should move to today. If it does not, the sidebar query is off
  for this account and only `primary-aeon-selection-v1` is left.
- **A task's row.** The dot's user-visible tasks ("Top of mind", "View all") come from the server. With none here it is
  unknown whether they reach `attachments` with `is_user_visible: true`. The owner would give the dot a task and repeat
  the check above.
- **One row or many.** Most accounts have one dot, so the list would show one row whose words are its last message. The
  design page shows two Dots rows ("Weekly metrics brief", "Inbox triage"), which the cache cannot back today.
