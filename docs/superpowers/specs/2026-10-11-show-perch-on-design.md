# Show Perch on: which screen Perch opens on

## Why

Today Perch opens on the screen the cursor is on (`ScreenChooser.current()`). With a laptop and an external monitor, the owner wants to choose, as Raycast does ("Show Raycast on": screen containing mouse, screen with active window, primary screen), so Perch shows up where they expect it every time.

## What the owner decided

- A Settings row, **Show Perch on**, with a menu of these choices:
  - **Screen with mouse**: the default, and what Perch does today.
  - **Screen with active window**: the screen holding the frontmost app's front window.
  - **One entry per connected display**, by name (`NSScreen.localizedName`, such as "Built-in Retina Display" or "LG UltraFine").
- The choice decides where **the shortcut** opens Perch, and where Perch **shows up by itself**: the live activity (full and wings), the welcome card after a break, a "Not now" coming due, and the update notice. The status item menu and Command+comma (Settings) count as the shortcut.
- **Hovering the top of any screen still opens Perch on that screen**, under today's rules. A screen with a notch always opens on hover. A display without a notch opens on hover only while "Hover opens on external displays" is on.
- **Hover opens on external displays moves into the Show Perch on menu**, as a switch at its end. It shows only while a display without a notch is connected, switches in place, and leaves the menu open. Its separate Settings row goes away, because the card must stay at or under about 300 pt tall.
- **A chosen display that is not connected** stays in the menu, greyed, still checked, marked "Not connected". Until it comes back, Perch follows the mouse. When it is reconnected, the choice applies again without anything to do.
- **A display is remembered by its own ID, not its position**, so plugging monitors in a different order keeps the choice.
- **With one display**, the row still shows, listing just that display.

The design page already shows all of this (`ui/design.html`, the "Which screen" group, plus "External display" → "Settings: Hover opens"). The page side is built in `ui/app.js` (`showHtml`, `bindShow`, `showMenu`). It posts `{type: 'setting', key: 'showOn', value: 'mouse' | 'window' | <display id>}` and `{type: 'setting', key: 'hoverExternal', value: Bool}`. It reads `settings.showOn` (String), `settings.displays` (`[{id, name, connected}]`), `settings.hasExternal` and `settings.hoverExternal`.

## Non-goals

- Hover on external displays regardless of the switch.
- A per-feature choice, such as the activity on one screen and the shortcut on another.
- Changing anything for "Screen with mouse": it must behave exactly as Perch does today.

## Anti-goals

- Perch jumping between screens while you work, other than to follow the setting.
- The live activity getting lost because the panel moved for a hover on another screen.
- Taking the keyboard, or asking for any new permission.

## Builder's calls (the owner did not decide these)

- **Display ID:** the display's UUID (`CGDisplayCreateUUIDFromDisplayID`). It stays the same across reboots and ports.
- **Active window:** read with `CGWindowListCopyWindowInfo`, using the front layer-0 window of the frontmost app. Window bounds need no permission. With no such window (the desktop, an app without windows), Perch follows the mouse.
- **Where the resting notch lives:** in the window and display modes, it sits on the target screen while nothing is open, so an activity appears there. When the cursor enters the hover zone of another eligible screen, the panel moves there, as today. When the cursor leaves that zone, the panel goes back to the target.
- **Order of displays in the menu:** the order of `NSScreen.screens`, with a disconnected chosen display last. Its name is remembered from when it was chosen.
