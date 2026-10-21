# Spike: Claude chats and Cowork

2026-10-21. Branch `claude/claude-cowork-support-spike-76da8c`. Can Perch show the Claude app's normal chats and Cowork
tasks next to coding sessions, and how do you keep them out when you don't want them?

## In short

- **Cowork works well.** Each task is a full Claude Code transcript on disk, so it gets the same card as a Code session
  (what it found, working or done, a question it asked). It opens straight to the task.
- **Chats work, but you only get the title.** The Claude app caches its last fetch of the 30 most recent chats on disk:
  title, time and Claude project. What was said stays on Anthropic's servers. The card can show the title and open the
  chat, and nothing else.
- **Filtering** uses the switch every agent already has. Cowork starts on. Claude chats start off: they aren't coding
  work, they can be personal ("Anniversary dinner ideas" in the notch while you share your screen), and their card has
  nothing to recap.

## Where the data is

| | Cowork | Claude chats |
|---|---|---|
| List | `~/Library/Application Support/Claude/local-agent-mode-sessions/<account>/<org>/local_<id>.json`: `title`, `isArchived`, `lastActivityAt`, `userSelectedFolders`, `cliSessionId`, `cwd` | `…/Claude/IndexedDB/https_claude.ai_0.indexeddb.blob/*/*/*`: one blob holds claude.ai's persisted react-query cache (`buster: conversations_v2:…`). Its `chat_conversation_list` query has `uuid`, `name`, `updated_at`, `created_at`, `project_uuid`, `model`, `is_starred`; `project_list` names the projects |
| Transcript | `local_<id>/.claude/projects/*/<cliSessionId>.jsonl`, normal Claude Code JSONL with `entrypoint: local-agent` | None. Messages are cached only for chats opened lately, in other blobs, and not in a form worth relying on |
| Format | JSON | Chromium IndexedDB value: `FF 11 02` (Snappy-compressed), then Blink's header (`FF 15 FE` + 12 bytes), then V8's structured clone |
| Freshness | Written as the task runs (FSEvents can watch it) | Rewritten every time any claude.ai query changes, and only while the app is open. A chat from your phone shows up once the app refetches |
| Pick up | `claude://claude.ai/local_sessions/local_<id>`, checked on this Mac | `claude://claude.ai/chat/<uuid>`, checked on this Mac |

The routes come from the app's own link handler (`app.asar`: the `ClaudeAI` host passes `/chat/<uuid>` and
`/local_sessions/…` through to the page). Not used: the claude.ai API, which needs the session cookie from the
Keychain-encrypted cookie store. Perch should never touch that.

## What the prototype does

Built on this branch, with tests (`ClaudeAppScanTests`, 6 cases, real-format fixtures, no personal data):

- `PerchCore/ClaudeApp.swift`: `CoworkSessions` (the task list), `ClaudeChats` (finds the newest cache blob, decodes it
  with a small Snappy decoder and a V8 structured-clone reader for plain data; anything unexpected reads as no chats), and
  ISO dates with six fractional digits.
- `SessionScanner.cowork` / `.chats`. A Cowork task is named after the folder you gave it, otherwise by its title (its
  own `outputs` folder counts as folderless). A chat's row is its title, with its Claude project in grey.
- Two new `Agent`s, `cowork` and `chat` (`onByDefault: false` for chat). `Prefs.enabledSources` keeps the ones that start
  off as `sources.optedIn`, so a new agent that starts on still starts on.
- `Restorer.link` for both links, the Claude icon for both, and the Cowork folder is watched (not the IndexedDB folder).
- The chat cache is decoded at most every 30 s (about 0.5 s in a debug build for the real 3.4 MB blob).
- Against the real data here: 30 chats with their titles and projects; Cowork tasks with real recaps ("Token fetched it
  and got back a single v4 UUID."), a question it left open, done states. Your Cowork tasks are all from June, so they're
  past the 14-day window and don't appear in your list today.

Design page, category **Claude app (spike)**: Cowork finished, A chat, The list with Cowork and chats, Settings: Cowork
and chats, Onboarding: Cowork and chats. Onboarding with all six tiles is 344 pt and Settings › Agents 342 pt, both
inside the panel.

## Settings and onboarding

- **Onboarding, Choose your apps.** Cowork and Claude chats are tiles like the rest, shown only when they were used on
  this Mac (their folder exists). The chats tile starts off and says only how many it found ("30 recent"), never titles:
  you see it before you've chosen anything.
- **Settings › Agents.** Two more rows with switches. Live status under them reads "a small hook in each agent", which
  isn't true for these two. Either word it "each coding agent" or leave it, since the hooks section is about the others.
- **Menu bar.** Nothing new. The same sources apply.

## What's open

1. **Hiding chats is all or nothing.** A finer filter could be "only chats in a Claude project" or "only starred". Both
   are in the cache (`project_uuid`, `is_starred`). I'd wait until someone asks.
2. **Is a chat worth a row at all?** Its card is a title and Open Claude. That covers *jump back in*, but not *where was
   I* or *what needs me*. Possible extra: say "Claude replied" when `updated_at` is newer than when you last opened
   it (`lastOpenedAt` sits beside it in the IndexedDB tree cache). Not built.
3. **Cowork in the session you're in.** Code sessions record `lastFocusedAt`. Cowork records don't, so Perch could
   speak up about a Cowork task you're watching in the app. That needs reading the Claude window's URL (Accessibility) or
   leaving Cowork's announcements off.
4. **Cowork questions and permissions** are read-only: hooks in `~/.claude/settings.json` don't reach Cowork's own config
   folder, and it asks inside the app. Reply probably works the same way as Code sessions (open the task, then paste into
   the composer), but I haven't tried it.
5. **Same icon.** Claude Code, Cowork and chats all wear the Claude icon. In Settings, Claude Code and Cowork sit next to
   each other with the same icon. A small corner mark (like a terminal session's) could tell them apart.
6. **Fragility.** The chat cache is an internal format of claude.ai (the cache key, the query names, Chromium's value
   wrapping). If it changes, chats quietly disappear (there are tests for a damaged blob), and nothing else breaks.
   Cowork's layout is plain JSON next to Claude Code's own format, so it's much less likely to break.

## Tested live (2026-10-21, 18:07 to 18:12)

One new Cowork task (fetch example.com, then ask a colour question), one chat ("pong"), with every file change under
`~/Library/Application Support/Claude` and every Perch hook call timed.

| Claim | Result |
|---|---|
| Cowork writes a transcript on disk as it runs | **Wrong for new tasks.** Nothing changed in `local-agent-mode-sessions`. New tasks are `cse_…` sessions the app lists from the server; `local-agent-mode-sessions` holds only the old (June) ones, and the app's own `cowork-local-sessions` list is now empty. |
| Where new Cowork tasks show up | claude.ai's persisted cache, the same blob as the chat list: query `cowork-remote-sessions` with `title`, `isRunning`, `liveStatus`, `lastActivityAt`, `unread`, `isArchived`, `userSelectedFolders`. Cached 3 s after the task's last activity. |
| What a Cowork task said | Cached in LevelDB (`000118.log`) as `cowork:cse_…`, the task's event stream with its final `result` ("The page title is **\"Example Domain\"**. For your colour, you chose **Blue**."). Needs a LevelDB reader. |
| Perch's hooks don't reach Cowork | **Holds.** No hook ran during the task. |
| Cowork doesn't record the task in front of you | **Holds, but there's something better.** No `lastFocusedAt`. Each task carries the app's own `unread` flag instead, false once you've looked at it. |
| A chat reaches the cached list quickly | **Holds** while the app is open: "Pong response" was cached at the second its reply finished. |
| A chat's words get cached | **Holds** for a chat you've just had: "pong" is in LevelDB's log. Again, it needs the LevelDB reader. |
| Scheduled runs each become a task | **Not tested.** The shortest repeat is hourly. |

What this changes:

- **Read Cowork from the chat cache, not `local-agent-mode-sessions`.** The blob Perch already decodes has the task list
  with its status (`isRunning`, `liveStatus`, `unread`). The prototype's on-disk Cowork reader only finds old tasks.
- **For the words of either one** (a task's result, a chat's last reply), Perch needs a small read-only LevelDB reader
  (log and table files) for `https_claude.ai_0.indexeddb.leveldb`. It covers what was open on this Mac lately.
- **`unread` can decide whether Perch speaks up** about a Cowork task, which answers the "task you're watching" problem.
- The cache also lists Claude Code cloud sessions (`sessions_api_list_sessions`: from the phone, with `status_bucket`
  and `unread`). They're another possible source, out of scope here.

## Recommendation

Ship Cowork (on by default), read from `cowork-remote-sessions` (see Tested live). Ship chats only behind the switch, off by default, or leave them out until question 2 has an
answer. The behaviour docs (`sessions.md`, `settings.md`) already describe the prototype.
