# Keyboard: the shortcut that opens Perch, and who has the keys

## The shortcut

- It is a tap of two or more modifiers (default Command+Option) or a key combo (`Shortcut`, with the rules: what is refused and why).
- `ModifierTap`: a tap counts only when pressed from nothing with no other modifier or key. Keys other apps' hotkeys take are counted by the system's key-down counter, so another app's Command+Option+Shift+L never opens Perch.
- `ShortcutRecorder` turns key events into a recording. It is recorded from Settings (Change opens a full-card page, `onbOpen` step 3 only) or onboarding step 3. `HotkeyService` applies it and pauses every Perch hotkey while recording.
- The new session shortcut is in [new-session.md](new-session.md); the live activity's keys in [speaking-up.md](speaking-up.md).

## When a card takes the keyboard

- A card you hover open takes it only when it shows something to answer (`cardTakesKeys`): otherwise a number or Esc lands in the agent's own prompt behind it, and Esc there dismisses the question.
- A card takes the keyboard once (on opening, or as the pointer comes onto it) and leaves it with whoever takes it next: Raycast closes the instant it loses focus.
- When another app takes the keyboard, or a launcher has it (`Quiet.launcherOpen`, an app other than the one in front, read through Accessibility), the card makes way (`makeWay`), except during onboarding or a reply.
