# The card: its words, selecting and copying

## Its words

- The title has its whole line. The status, in words, ends the grey line under it (the project and what you were doing).
- The body is the agent's outcome (`Recap.outcome`), not your prompt.
- No model writes the card. Its words are the session's title and the agent's own: a long reply is read for its gist (a Summary or TL;DR first; code, tables and openers like "Let me…" skipped), and a reply with nothing to quote gives way to what the agent did (`Work`, `Recap.did`) or to its short answer.
- On-device summaries (Apple's model) were tried and removed: they dropped facts and made others up.
- Next shows only a step the agent stated, a question it asked or a plan waiting (`Recap.statusAndNext`).
- While a session works, the card says what it last said it is doing, and a Now row shows the step (`Activity.step`) with a Thinking Orb beside it in the character's colour whose state follows the step (`orbFor`; `ui/orbs.js` is the MIT plain JS build of thinkingorbs.com, vendored). Background work it waits on: [status.md](status.md).
- Permission asks in a terminal show on the card but are answered there.

## Preview: the whole last message

- The card's body is a gist. Under it, Preview (Space) shows the agent's whole last message on the card: the same view a reply has (`showSaid`, markdown and tables alike, your own last message above it as a bubble), without the field, as tall as the panel's 440 pt allows (app.js `fitPreview`). A message that fits shows whole; a longer one scrolls with a soft edge.
- It opens from Space, Preview, or a click on the summary (`.o-h`, `.o-c`); dragging over the words to select them does not open it. On the notch, a finish's title opens its card on Preview, and the shortcut that opens Perch opens its card, where Space previews ([speaking-up.md](speaking-up.md)). In the list, Space with nothing typed previews the row you are on, as Finder does; once you have typed, Space is a space in the filter. Not on a card with a request (permission or question): that card is for answering.
- Space again closes it, as Quick Look does. Up and Down go a few lines, Page Up and Down (Fn+Up and Down) a page, Command+Up and Down go to the ends (`previewKey`, Swift's key monitor while `previewOpen`). Command+C copies what you selected, else the whole message as written, markdown and all (`copy` to Swift's pasteboard); a selection brightens and the Copy button reads Copied for a beat. R turns it into a reply with the message where you scrolled it; Return opens the session; Esc or Left goes back where it came from, the card or the list on the same row.
- While Preview is open the card is yours, as with a reply: it does not fold on its own or close when the pointer leaves.

## Selecting and copying

- What the agent said (the card's body, Next, an ask's words, the expanded reply) can be selected, and Command+C copies it. Perch has no Edit menu, so the key monitor sends `copy:`. A copy brightens the highlight for a beat.
- The page draws the highlight (app.js `hlDraw`, input.css `.hl`): a rounded piece per line in the character's colour lifted toward white (`--hl`), screened over the words, cut to what shows (the reply's scroll, a table's window), list markers left out. The system's own selection is hidden underneath and is what gets copied.
- In a field (the reply, a new session's prompt) the system's own selection shows, in the same colour, for a double or triple click or Command+A. A refresh that changes nothing on the new session card does not draw it again (`newRender`), so the prompt keeps its selection and caret.
- While words are selected the card stays open, with no countdown and the pointer free to leave (`textSelected`, app.js `selCheck`). The card's words are put in only when they change (`setWords`), so a refresh does not drop the selection.
