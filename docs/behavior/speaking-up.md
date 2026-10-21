# Speaking up: the session you are in, the live activity, the welcome card

When Perch shows itself without being asked. The keyboard rules for it are in [keyboard.md](keyboard.md), which screen it shows on in [displays.md](displays.md).

## The session you are in

- Perch never nudges about the session you are in, or may be in (`NotchController.youAreIn`; `PERCH_TRACE=1` logs `Perch in:`).
- `FocusProbe` reads what is in front, a second apart, off the main thread: the focused cmux surface, a Terminal or iTerm2 tab's tty, Ghostty's folder, herdr's focused pane, the pane a tmux client shows, the Claude window's session (Accessibility). A reading older than 3 s is not trusted.
- `Focus` compares a running session's Spot (cmux surface, herdr pane, tty) with what is in front (Looking). Unsure means every live session in that app is a maybe.
- The Claude app's own `lastFocusedAt` counts too: the session it focused last is the session you are in.

## The live activity

- While you work, an answer or a request in a session you are not in shows as a live activity (`UISnapshot.activeIds`, app.js `inside`). The notch grows with the project beside the camera and what happened; below, the session's title and a row of buttons on Command+Option keys registered only while it shows (app.js `activity`; `./scripts/run.sh --activity` plays it).
- Open <app> at the right of the row opens the session in its app, on Command+Option+O on every row. With three choices on the row there is no room for the button, so the key works alone, and hovering the question says so. The key shows on no button when Perch's own open or new-session shortcut uses it or another app holds it. Clicking the question opens it on the card, all of it; so does the shortcut that opens Perch, on the row or in the wings.
- A finish with a message to read: its title, clicked, opens its card on Preview, the whole message ([card.md](card.md#preview-the-whole-last-message)); hovering the title says so. From the keyboard, the shortcut that opens Perch opens the finish's card (then Space previews), as it does a question's ([keyboard.md](keyboard.md)).
- Where Pick up is already a button (a finish), a small cross at the left of the row puts it away. Command+Option+. puts any row away.
- The button under the pointer is lit from where the pointer is (app.js `markAct`), not WebKit's hover, which stays on a button the pointer left when the panel was never clicked.
- A finish folds away. A request folds to wings until answered. A stop on an error (nothing to answer) says so once and folds away, and does not come back for the same error (`actErr`).

## Sent, or Didn't send

- An answer from the notch or a card says it went: the chosen button lights for a beat, then the notch folds to one line, the session on the left and Sent with a blue paper plane on the right, whatever the answer (a choice, Allow, Deny), for about two seconds (app.js `sentShow`). From a card, the plane waits until the notch has settled.
- It is said to the end: a request or a finish that arrives meanwhile, or while the button lights, is said in full right after it (`sentDone`, measured against what had been said when you answered, `sentBase`).
- A reply sent from the notch ends the same way, after its words have flown up into the notch (details in [replies.md](replies.md#sending)).
- If the answer reached nothing (the request was settled or let go a moment before, `HookServer.answer` reports it), the line says Didn't send in orange (`notSent`).

## The welcome card

- It speaks up only on return from a break, and only if a session changed since you last saw it (finished, asked, stopped) and since your last break or within the last day (`WhileAway.newsSince`).
- Older is history: a guessed "needs you" from then reads as idle (`Project.settled`). So does one you have seen once you look at a later change in another session (`Project.movedOn`). A question you have seen never opens the card ahead of a fresh finish (`urgent`).
- Never during a call, camera or presentation, nor while a launcher such as Raycast has the keyboard (`Quiet`; it shows once that is over), and never during a "Not now".
- "Seen" is per session, in UserDefaults: a second on the welcome card, a Pick up, or being the session you are in. A session you had in front in the Claude app since it changed (`lastFocusedAt`) is not news.
