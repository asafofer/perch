# Speaking up: the session you are in, the live activity, the welcome card

When Perch shows itself without being asked. The keyboard rules for it are in [keyboard.md](keyboard.md), which screen it shows on in [displays.md](displays.md).

## The session you are in

- Perch never nudges about the session you are in, or may be in (`NotchController.youAreIn`; `PERCH_TRACE=1` logs `Perch in:`).
- `FocusProbe` reads what is in front, a second apart, off the main thread: the focused cmux surface or agterm pane, a Terminal or iTerm2 tab's tty, Ghostty's folder, herdr's focused pane, the pane a tmux client shows, the Claude window's session (Accessibility). A reading older than 3 s is not trusted.
- `Focus` compares a running session's Spot (cmux surface, agterm pane, herdr pane, tty) with what is in front (Looking). Unsure means every live session in that app is a maybe.
- Cursor's Agents window names its chat in a button ("Chat title. …"), which `CursorWindow.showingNow` reads through Accessibility; that chat is the session you are in. A Cursor window that cannot be read makes every Cursor chat a maybe.
- The Claude app's own `lastFocusedAt` counts too: the session it focused last is the session you are in.

## The live activity

- While you work, an answer or a request in a session you are not in shows as a live activity (`UISnapshot.activeIds`, app.js `inside`). The notch grows with the project beside the camera and what happened; below, the session's title and a row of buttons on Command+Option keys registered only while it shows (app.js `activity`; `./scripts/run.sh --activity` plays it).
- Open <app> at the right of the row opens the session in its app, on Command+Option+O on every row. With three choices on the row there is no room for the button, so the key works alone, and hovering the question says so. The key shows on no button when Perch's own open or new-session shortcut uses it or another app holds it. Clicking the question opens it on the card, all of it; so does the shortcut that opens Perch, on the row or in the wings.
- A finish with a message to read: its title, clicked, opens its card on Preview, the whole message ([card.md](card.md#preview-the-whole-last-message)); hovering the title says so. From the keyboard, the shortcut that opens Perch opens the finish's card (then Space previews), as it does a question's ([keyboard.md](keyboard.md)).
- Where Pick up is already a button (a finish), a small cross at the left of the row puts it away. Command+Option+. puts any row away.
- The button under the pointer is lit from where the pointer is (app.js `markAct`), not WebKit's hover, which stays on a button the pointer left when the panel was never clicked.
- A command on the row is said without the plumbing that only shapes its output for the agent: `npm run build 2>&1 | tail -n 30; echo "EXIT: $?"` reads `npm run build` (`Ask.brief`). The card shows it in full.
- A finish shows only while Finished is on in Settings, Notifications (`notifyOff`, app.js `muted`).
- A pull request that starts needing you (Checks failing, Changes requested, Merge conflicts) is announced as `ci`, unless Checks failing is off in Settings, Notifications ([pull-requests.md](pull-requests.md)).
- A finish folds away. A request folds to wings until answered. A stop on an error (nothing to answer) says so once and folds away, and does not come back for the same error (`actErr`).

## Sent, or Didn't send

- An answer from the notch or a card says it went: the chosen button lights for a beat, then the notch folds to one line, the session on the left and Sent with a blue paper plane on the right, whatever the answer (a choice, Allow, Deny), for about two seconds (app.js `sentShow`). From a card, the plane waits until the notch has settled.
- It is said to the end: a request or a finish that arrives meanwhile, or while the button lights, is said in full right after it (`sentDone`, measured against what had been said when you answered, `sentBase`).
- A reply sent from the notch ends the same way, after its words have flown up into the notch (details in [replies.md](replies.md#sending)).
- If the answer reached nothing (the request was settled or let go a moment before, `HookServer.answer` reports it), the line says Didn't send in orange (`notSent`).

## Clicking the character

- The small character at the top left of an open card, the switcher, Settings and the other cards reacts to a click (app.js `crClick`, styles in input.css next to `.cr-in.hops`). Its click target reaches 4 px past the drawing. At rest it is hidden behind the notch and the panel ignores the mouse, so there is nothing to click.
- Six reactions, each a different one from the last (never the same twice in a row): giggle (the wobble the onboarding preview has), hops (two low hops, kept under the screen edge), dash (it runs right along the top and shrinks out of sight at the notch's edge, pops out there a moment later and trots home; the distance comes from the notch's width), wink (a head tip, one eye smiles shut, a sparkle), startle (wide-eyed, it shies back and shivers) and nap (eyes shut, two z's, a hop awake).
- A click while one plays is ignored. A snapshot that arrives meanwhile leaves its face alone (`crPlay`); the face comes back from the snapshot when the reaction ends. With reduced motion it only smiles for a moment. The design page's Character category plays each (`Click: ...`; `perchDev.mascot(name)`).

## The welcome card

- It speaks up only on return from a break, and only if a session changed since you last saw it (finished, asked, stopped) and since your last break or within the last day (`WhileAway.newsSince`).
- Older is history: a guessed "needs you" from then reads as idle (`Project.settled`). So does one you have seen once you look at a later change in another session (`Project.movedOn`). A question you have seen never opens the card ahead of a fresh finish (`urgent`).
- Never during a call, camera or presentation, nor while a launcher such as Raycast has the keyboard (`Quiet`; it shows once that is over), and never during a "Not now".
- "Seen" is per session, in UserDefaults: a second on the welcome card, a Pick up, or being the session you are in. A session you had in front in the Claude app since it changed (`lastFocusedAt`) is not news.
