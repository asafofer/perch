# Settings: the list, its pages, and Send feedback

Which screen Perch shows on is in [displays.md](displays.md); the shortcut recorder in [keyboard.md](keyboard.md); the
Version row's update states in [updates.md](updates.md).

## The list

- The gear on the card or the list, or Command+comma, opens a short list: Shortcuts, Agents, Status, Notifications, Character,
  General, Version, Send feedback. Each row says what it is set to now (the shortcut's keys, the agents' icons, the moments
  the notch announces, the character's name, the screen it shows on), so the list alone answers most questions.
- Reply and shortcuts, needs access, is the first row while Accessibility is off, with Allow: the one thing to do there.
- Version is the build ("0.4.3 (210)") and, on the right, where its update stands: Check for updates, what is out with
  Update, a ring while it downloads, Restart to update, a failure in orange with what to do. A local test build has no
  updater: the version only, and no row when the notch already says it is a test build.
- Character opens the character picker in place; Done comes back to its row.
- All of it is drawn by the page (app.js `settingsRender`, `setPage`); Swift sends the values (`settingsState`) and does
  what each change asks (`setting`, `source`, `notify`, `hooks`).

## Pages and the keys

- Up and Down choose a row, Right or Return opens a page, Left or Esc comes back to the list on the row you left. On the
  list Left or Esc goes back to the card or list Settings came from, or closes it. The page slides in from the right and
  back from the left (transitions.dev page side by side).
- On a page every setting is a row of its own, with no menu to drop down, so a page is only as tall as it needs:
  - Shortcuts: Open Perch and New session, each with Change (the recorder) and Reset for a recorded one.
  - Agents: what Perch found comes first, in alphabetical order, a line for each agent or app it has seen a session of
    (`isFound`: a count above nothing; herdr, tmux, cmux, agterm and Conductor are listed like the agents) with a check and
    how many sessions it has. Past six they go two to a line. Under them Others, one row that opens a popover list as wide as
    the rows: everything Perch supports that it has not seen, alphabetical, one to a line, off until you switch one on. It
    shows five lines and scrolls past that, fading at the edge that has more; the card grows only by what the list needs
    past the rows. Closed, the row says "12 more" or, once some are on, "2 on". With nothing found yet there is a quiet
    line and Others ("16 to choose from"). Up and Down choose in the popover, Return switches one, Left or Esc closes it.
    With all sixteen found the page is 348 pt. Kept as `sources.disabled`, and `sources.optedIn` for Claude chats and for
    what is in Others, which start off.
    Onboarding's apps step is the same: it opens while the first scan runs ("Looking for your sessions", one quiet line),
    then what it found rises in as tiles, ticked (chats are not), with the names of their sessions, under "Here is what Perch
    found". Others is the grid's last tile, quieter than the rest, so it fills the slot beside an odd one out; it opens the
    same five-line popover under it. Past six found the tiles are slim with no second line, and past ten the list scrolls.
  - Status: Live status as a toggle, and Pull requests (Off, Marks, Checks: [pull-requests.md](pull-requests.md)), which sat
    under the agents until the list could outgrow the panel. Its row on the list says "Live, PR marks" (or checks, or no PR
    marks), or "Live status off". The reason line's Settings link on a question Perch cannot answer opens this page.
  - Notifications: one row, Notify me about, with the lit moments (`NotifyKind`) as small coloured icons and a chevron; it opens
    a menu over the rows below, a check for each moment, and the card grows to hold it (Return opens it, Up and Down choose,
    Return switches, Left or Esc folds it). Checks failing is the last, greyed with "Needs Checks" until Checks is chosen.
    Then Welcome back after and Questions stay for.
  - General: Open at login; Show Perch on as a list with one check; Hover opens on external displays while one is connected.
- Return or Space flips a switch, picks a screen or presses a row's button. Left is always Back: a segmented choice moves
  with Right (to its end) or Return (round again from the start).
- The page's title sits under the notch's line with a Left key beside it: next to the hardware notch there is room only
  for "Settings", which steps back and is a way back too.

## Send feedback

- The last row opens a page with a field for your words, files along its top, an optional email, and a switch that says
  plainly what else goes: "Include Perch 0.4.3 and macOS 26.1", on by default. The page has the keyboard while it is open
  (`feedbackOpen`): Return sends, Shift+Return is a new line, Esc (or Left in an empty field) goes back and keeps it all as
  a draft, which the row says.
- Files come as on a reply: dropped on the card, pasted (a file copied in Finder, or a picture on the clipboard), or with
  Attach or Command+O (the Mac's picker). Perch is the app in front while the page is open, as for a reply (the picker can
  only come forward then), and gives the front back when it closes. Folders are left out. Each chip wears the file's thumbnail (`AppIcons.file`, Quick Look's for
  anything that is not a picture).
- Perch sends 4 MB of files at most (a Vercel function takes 4.5 MB per request). Pictures go smaller first, their longest
  side 2000 px as JPEG (`FeedbackSender.size`, `attachment`), and the page shows the size each goes at. A file that takes
  the total past the limit turns orange with its size, Send stays faint, and the line under the switch says to remove it or
  email it instead (`Feedback.fits`, the page's `fbBig`).
- An email that does not look like one (`Feedback.isEmail`, the page's `fbMailBad`) is said once you leave the field or
  press Send, never while you type: the field and the line turn orange until it is right or empty.
- Sent: the page clears and your words rise into the notch as a bubble, which swallows them with a green ripple, the
  character hopping (as a reply to a terminal does). The list comes back on the Send feedback row, which says Sending with a
  spinner, then a green check and Sent. Thank you, the card glowing green for a moment.
- Not sent (offline, the function refused it): the row says Couldn't send in orange and the card glows orange. Open it and
  everything is there, with Try again and Email it instead.
- Email it instead, beside a file too big or a failure, writes to `hello@perchapp.dev` (Resend receives it and the function's
  `api/inbound.ts` sends it on, Reply-To the sender) and uses your own mail app (the one that opens mailto: links). Mail gets
  a new message (`NSSharingService` compose) with the words, the versions and the files as they are; any other app (a
  browser's Gmail, Spark) gets a mailto: link, which cannot carry files, so Finder shows them alongside to drag in. Perch
  steps aside and does not bring back the app you were in over it.

## Where feedback goes

- `FeedbackSender.send` posts a multipart form (`Feedback.body`: `text`, `email`, `version`, `macos`, each `file`) to the
  feedback function, `feedback/api/feedback.ts` in this repo, deployed on Vercel. It checks the same limits again and
  emails it through Resend to `FEEDBACK_TO`, Reply-To the sender's email when it looks like one. Nothing is stored.
- The address is `FeedbackSender.endpoint`; `PERCH_FEEDBACK_URL` points one run elsewhere (a `vercel dev`). Setting it up
  (keys, the rate limit) is in `feedback/README.md`.
- The design page's Settings and Feedback categories play every state; the sample files' thumbnails are drawn there.
