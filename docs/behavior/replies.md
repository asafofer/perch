# Replies: answering a session from the card

Selecting and copying the agent's words is in [card.md](card.md). Replies into herdr, tmux, cmux and Conductor are in [agents.md](agents.md).

## What the reply shows

- The agent's own last message as written (`Project.said`, line breaks kept), with your own last message above it as a bubble, a scroll up (`Project.asked`).
- Markdown (`mdLines`): a table scrolls in its own window both ways, header kept (`mdTable`). Bullet (`-`, `*`, `•`) and numbered lists draw with grey markers. Code takes the character's colour (`.md-code`, `--cr`). Deeper indents nest, an indented line carries on its item, a list may follow a bold line with no blank line, and a `#` heading is a bold line.

## Drafts and putting it away

- What you type in a reply is that session's draft until sent (`drafts`, in memory): closing the card keeps it, Esc and R bring it back.
- Command+Option within five minutes of putting the card or list away brings it back as it was: the same session's card, or the list with its filter (on its top row, as when opened), a reply open with its words (`PutAway`). Resting on the notch brings back a reply you were writing.
- Pick up, a reply sent, an answer or Not now forget it.

## Files and pictures

- A file pasted from Finder or dropped on the card is attached: a chip over the field with the file's own icon (a picture's thumbnail, `AppIcons.file`, sent after the paths as `fileIcons`), its name and an x. Backspace in an empty field takes the last. The chips keep to one line and scroll sideways.
- A picture on the clipboard with no file behind it (a screenshot taken to the clipboard) is saved as a PNG in `~/Library/Application Support/Perch/Pasted` and attached the same way. It is deleted ten minutes after its message is sent (time for the agent to read it), kept when a new session does not start, and anything left is swept after a day (`Clipboard.pastedFiles`, `letGo`). Text on the clipboard wins over a picture beside it.
- When sent, each path follows your words, quoted if it has spaces (`CardWebView`, app.js `attChips`, `withFiles`). The design page's stand-in icons by kind come from `--design-icons`.
- A press outside the card closes it on release, so a file dragged from Finder can still land on it. Files dragged to the notch open the card like a hover.
- Files over the card open its reply and light the field, more so right on it, while the character watches them (app.js `dragOver`; the design page plays a pretend drag).

## Sending

- To a terminal: the card clears and the notch gulps the words.
- A reply that went in the background (typed into its terminal, a closed one reopened with it, or taken by Claude's composer) ends like an answer: the card folds to the Sent line ([speaking-up.md](speaking-up.md#sent-or-didnt-send)). Swift says so (`replying`), so the page never claims more than happened.
- A reply that falls back to pasting says no Sent: the line goes without a word (`replyHanded`) and the session comes forward, or Reply copied says the rest. There is no Didn't send for a reply, since the fallback always takes it on.
- To a Claude app session, it goes in with Claude's window behind (`ClaudeComposer`): it presses the session's sidebar row, fills the ProseMirror field (a draft already there is set aside and put back after Send), presses Send, then goes back. The page's address must end in `local_<id>` before it writes and before Send, otherwise it falls back to pasting. It leans on Claude's page internals, so a Claude update can send it to the fallback.
- Whenever Perch has to bring an app forward to reply (the paste fallback, a session resumed in a new terminal tab), it puts you back in the app, window and Claude session you were in (`WhereYouWere`). A fallback never presses Return over a draft.
- Without Accessibility, Send reads Allow and send and holds the reply until access is on.
