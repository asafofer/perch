# New session: starting a session from the notch

## Opening it

- Option+Command+N from anywhere (a Carbon hotkey, id 5, recordable from its Settings row; `Prefs.newShortcut`), or New session in the list's footer, opens the `newSession` phase.
- It asks which agent (the Claude and Codex apps and the command line agents found on this Mac, `NewSession.choices`), which folder, then the prompt.
- Folders: the folders sessions ran in (a worktree counted as its repo), No project, or the Mac's own picker. The Claude app cannot be asked for no folder, so for it that row is Let Claude choose: given none, Claude uses the folder picked in its own new-session screen.
- It starts on the agent and folder of the session you are looking at (the row or card you were on, else the one in front of you), else what you started with last (`NewSession.defaults`).
- Typing narrows the agents and the folders.

## While it is open

- Nothing else changes it: the agents and folders hold still (a scan that moves a folder to the top neither reorders the rows nor changes the one chosen, app.js `newApply`), and it never makes way for an app that comes forward (`makeWay`). Only Esc or a click outside closes it.
- A file dropped on it or pasted from Finder is attached as on a reply ([replies.md](replies.md)), chips along the top of the prompt. While the agent or folder is still being chosen, the file goes on to the prompt: the row under it lights up and says Drop to start, and a drop there picks it (`nwPaths`, `nwDropRow`).
- Return starts it and leaves you where you are. Command+Return takes you there.

## Starting in the Claude or Codex app

- The Claude app opens `claude://code/new?q=<words>&folder=<path>`, the Codex app `codex://threads/new?prompt=<words>&path=<path>`. Both put the words in a new session's message field and come forward, so `NewSessionStarter` presses Send through Accessibility and Perch puts you back (`WhereYouWere`).
- A link that names a folder makes the Claude app ask to trust the workspace (Codex asks for a folder it has not seen). That is yours to answer, so Perch never presses it. The notch says Confirm in Claude; started from the list, the list folds into that line, since the app now has the keyboard.
- Claude asks either as the link opens or on Send. Asked as the link opens, Perch waits for your answer: Trust leaves Claude's folder menu on your folder and the words in the field, and Perch presses Send; Cancel puts the menu back on the folder it had before, so Perch leaves Send to you and a Cancel stays a Cancel; the notch says Didn't start at once and keeps your words, as below. Codex shows no folder to check, so after its question Send is yours. Trust pressed through Accessibility was tried: Claude then starts the session with no folder.
- Claude's link names the folder, but Claude (2.42) starts the session with none, in a scratch workspace, while its menu by the field shows the folder's project. So Perch chooses the project itself in that menu ("Environment: perch"; Claude calls its projects environments), under More when it is not among the recent ones, and then presses Send. The project for a folder comes from Claude's own list, `ccd-session-presets.json` (`NewSession.claudeProject`: a local one on that folder, the most recently used). Claude has none for the folder: Send is yours, the notch says Confirm in Claude, and a new session anywhere counts.
- After a trust question, Perch chooses the project only once the menu shows it (your Trust); the menu back on another folder is your Cancel.
- Perch presses Send only while Claude's menu by the field names the project you chose (`folderMenus`: a menu's title, "Folder: ~/path", or "Environment: name"), else it leaves Send to you. The session then starts as Claude starts one in that project, in a new worktree when the project makes them. While it waits on that, a new session of the agent counts wherever it runs, since you can pick another folder there (`NewSession.started`, `anyFolder`).

## Starting a terminal agent

- It opens in a new window of your terminal (a new session in agterm): `claude --session-id <id> '<words>'`, `codex`, `opencode --prompt`, `pi --session-id`.

## Started, or not

- It is Started only once the scan finds the new session (`NewSession.started`: one not seen before, of that agent, in that folder, begun since; by id where the agent takes one), else Didn't start after 40 s, and your words come back as the draft.
- Opened from the list, it goes back to the list at once and the session is a row from the moment you press Return (`pendingRow`, `pending` in the snapshot): your words as its title, grey with the passing light of a step at work (`.shimmer`), Starting, then Started with the paper plane. That row is on the arrows' path; Return there brings its app forward (`pendingPicked`, `showStarting`).
- Opened from anywhere else, the card folds into one line like a reply's Sent.
