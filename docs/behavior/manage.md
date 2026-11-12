# More: rename, archive or delete a session

## Opening it

- On a card: the More button in its top bar (beside Settings, so the footer keeps its room for Reply, Preview and Open), or Command+K. In the list: More at the right of its footer, or Command+K, on the row you are on. Letters type into the list's filter, so the list's key is Command+K, the one Raycast uses for its actions.
- A small popup opens, its right edge under the card's button (over the list's) (`manageMenu` in app.js; the card behind it dims, `.m-dim`). Rename, Archive and Delete, each with its icon and letter; Up and Down choose a row and Return does it. Esc or a click elsewhere closes it.
- Perch is in front while it is open, as for a reply (`frontForReply`), the card does not close by itself (`manageMode` holds it) and the keys go to the popup (`manageKeyName`).
- Only what the session's route can do is offered (`SessionManage.actions`, sent as `manage` on each project). A session with nothing to offer has no More button.
- Archive and Delete ask once more, in the popup ("Archive this session?", "Delete this session?"; Return says yes, Esc goes back to the rows). Rename is a field: on the card in the footer, in the list inside the popup. Return renames.
- After Archive or Delete the session leaves the list at once and the card goes to the list; a line over the footer says how it went (Renamed, Archived, Deleted, or why not; a failure stays longer). It is the character's word when nothing is open.

## What each source does (`SessionManager`, off the main thread)

| Session | Rename | Archive | Delete |
|---|---|---|---|
| Claude app (Code) | its row menu, through Accessibility | its row menu | its row menu |
| Claude Code in a terminal | a `custom-title` record appended to its transcript | none | the transcript to the Trash |
| Codex (app and terminal) | `codex app-server`: `thread/name/set` | `thread/archive` (its file moves to `archived_sessions`) | `thread/delete` |
| OpenCode (app and terminal) | `opencode serve` on a free port: `PATCH /session/<id>` title | `PATCH` with `time.archived` | `DELETE /session/<id>` |
| pi | a `session_info` entry appended, hung under the last entry | none | the session file to the Trash |
| Cursor, Claude tasks and chats, Conductor workspaces, sample data | none | none | none |

- A terminal Claude Code, Codex, OpenCode or pi session at work (a running process, or a status of running) is only renamed: its files are not taken out from under it. The Claude app's own sessions keep all three, as its own menu does.
- Delete of a file (Claude Code, pi) goes to the Trash, so it can be put back. Codex and OpenCode delete for real.
- The Codex and OpenCode routes start a short-lived server of their own, so their desktop apps may show the change only when they next read their list.

## The Claude app

- Its row menu is a web popover that exists only while the app is the active app (opened with the app behind another, `AXShowMenu` succeeds and nothing shows). So Claude comes forward for the moment it takes, the menu's note says so (Brings Claude forward), and what was in front before comes back (`ClaudeComposer.manage`).
- The menu is found from its first item, where focus usually goes when it opens; when focus does not get there, by the open popup itself (`group/menu-popup`, `openPopup`). Afterwards the list or card takes the keyboard back if it had it (`manageHadKeys`), since bringing Claude forward and back leaves it with the app you were in.
- Its items are not a menu element: each sits in its own group. Focus goes to the first item when it opens; the nearest ancestor holding Archive is the menu.
- The row is found by the session's title (never its project's name: a group header carries that). Rename types into the field the row turns into and presses Return; the app takes the new name only after Return, so the row's new title is the check. Archive and Delete are checked by the row leaving the sidebar. The app writes `isArchived` into its session file a few seconds later.
- Needs Accessibility. Without it, or when a step does not look as expected (no row, or two sessions with the same title), nothing is changed and the line says why. Keys are sent only while the Claude app is in front.
- Only one action runs at a time: Command+K and the menu are ignored until it is done, and the card stays open meanwhile.

## Trying a route

`build/Perch.app/Contents/MacOS/Perch --manage rename|archive|delete <agent> <session id> [name]` runs a route without the menu, for a session made for the purpose (`claude-app <local_ id> <title> [name]` for the Claude app). It prints ok or why not and quits.
