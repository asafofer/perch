# Pull requests

A session shows the pull requests it worked on: a small mark beside its time in the list, and at the right of its grey line on the
card. Icon only; the words and the title are in a label on hover. Code: `PullRequests.swift` (core), `PullRequestState.swift`
(the app's side), app.js `PRMark`, `prHover`.

## The mark

- The icon is the state, in GitHub's colours: green open, purple merged, red closed, grey draft. It turns orange when the pull
  request is yours to act on (`PullRequest.needsYou`: checks failing, a review asking for changes, merge conflicts).
- A session with several shows the one that matters most (`PullRequests.top`: needs you, open, draft, merged, closed) and a
  small count.
- Hovering it (or a card hovered open, where WebKit sends no pointer: `hoverAt`) opens a label, one block per pull request: its
  title when known (Checks), the state in the icon's colour, and `repo #number`. The label stays while the pointer is on it, each
  block lights, and a click opens that pull request on GitHub (`openpr`: https on a GitHub host only). Clicking the mark opens
  the top one.
- No glow dots and no ellipsis: a long title fades at its end (`.fade`), and only when it does not fit.

## Where they come from

- **Marks** (the default): the Claude app's own list, the `prs` of each session file in `claude-code-sessions` (`number`, `url`,
  `repo`, `state` OPEN or MERGED, `branch`, `own`). No login and no network. The app lists what a session touched too, a pull request
  it only read among them, so only the session's own are kept: `own: true`, or where the app does not say, a pull request on the
  session's own branch. One the session opened that the app does not list is found in its log, as for the other agents.
- The app keeps an open pull request's state only while the session is in use (6 of 13 saved as open were merged, all in sessions
  idle for 8 days or more). So without Checks, an open or draft one from a session idle for more than two days is not shown
  (`PullRequests.staleAfter`); merged and closed are final and always shown.
- **Every other agent**: found in the session's own log (`PullRequestScan`), as the address a command that opens a pull request
  printed: Claude Code's `tool_use` and `tool_result` ids, Codex's `call_id`, pi's `toolCallId`, OpenCode's one record with the
  command and its output. Only the result of that call counts: an address in your message, a document, `gh pr view` or a search is
  never taken. Logs are read as they grow, from where the last read stopped. A Claude app session the app lists no pull request for
  is read the same way. The state is not in the log, so these show once GitHub has been asked (Checks): without it nothing shows
  for them (`stateKnown`).
- **Checks** (off until chosen): Perch asks GitHub through the GitHub CLI's login (`gh pr view --json … -- <url>`, read only; the
  address follows `--`, so it is never an option, and only GitHub addresses are asked). It runs `gh` from where it is installed
  (Homebrew's folders, then a login shell) since an app has no PATH. It gives titles, checks, reviews and conflicts, and corrects a
  state the app has wrong. Checks count only when they hold the merge back (GitHub's UNSTABLE means only optional ones fail), and
  skipped or neutral ones say nothing.
- `PullRequestChecker` asks only for what the list shows, three at a time, and remembers: an open one for a minute, a closed one
  for three (it can be reopened), a merged one for six hours, a failure for two minutes. A check run again is listed once for each
  run: the newest of each workflow and name stands. Its answers refresh the list (`onUpdate`).
- Checks needs the CLI installed and signed in (`GitHubCLI.availability`: `gh auth status`). Without them Checks is greyed in
  Settings with the line saying what to do, and marks go on working.

## Needs you

A pull request that needs you is a fact GitHub gave, not a guess from a transcript, so it is not turned into history by `settled` (a
"needs you" from before your last break) or `movedOn` (you looked at another session since): it stands while GitHub says so.

With Checks on, a session whose pull request needs you reads as needing you ("Checks failing on #448"): it sits under Needs you with
the `!` ring and an orange mark. Not a session that is working or asking something already. The notch announces it like any
other moment, as `ci`, in words that say which ("Changes requested on #126") (Settings, Notifications, Checks failing), which only stops the announcing: the list and the card still say it.

## Settings and onboarding

- Settings, Agents, Pull requests: Off (no marks), Marks (the default), Checks. Keys: Right moves along the choices, Return comes
  round again. Kept as `pr.show` (on by default) and `pr.checks` (off).
- Onboarding gets a step after Live status, "Know when a pull request needs you", with one switch, only when the GitHub CLI is
  signed in (eight steps then, seven otherwise). Turn on, Skip or Next; turning it on also turns marks on.

## Testing

`PullRequestsTests` covers the parsing, the stale rule, the `gh` wrapper (with a stand-in runner), the cache and what a session
shows. `Perch --dump` prints each session's pull requests and, with Checks on, asks GitHub first (`PERCH_DUMP_MAX=60` lists more
sessions). Run it from `build/Perch.app` so it reads the app's settings.
