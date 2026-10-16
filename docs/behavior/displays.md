# Displays: which screen Perch shows on

## Show Perch on

- Settings → Show Perch on (`Prefs.showOn`, `ScreenTarget`) decides where the shortcut opens Perch and where it shows up by itself (live activity, welcome card, a snooze coming due, an update):
  - the screen with the mouse (the default);
  - the screen with the active window: the front layer-0 window of the app in front, from the window list (`FrontWindow`); none means the mouse;
  - one display by its UUID (`NSScreen.displayID`). One not connected stays in the menu greyed, with the name it had (`Prefs.showOnName`), and until it is back Perch follows the mouse.
- `ScreenChooser.target()` is that screen. `rest()` is where the panel waits while nothing is open: with the mouse it follows the cursor as always, otherwise it waits on the target.
- `--dump` prints the screens, their ids and where Show Perch on points now.

## Hover

- A hover always opens Perch on the hovered screen: in the fixed modes the panel moves to a screen whose hover zone the cursor enters and goes back once it leaves (`followHoverWhileFixed`).
- Hover only counts on the screen the cursor is on, because the hover zone reaches above its screen's edge (`overNotch`, `NotchGeometry.hovering`).
- `ScreenPicker` finds which display the cursor is on with the top edge counted: a cursor aimed at a notch rests at y == maxY, which `CGRect.contains` leaves out.

## Displays without a notch

- A display with no notch shows nothing at rest: Perch opens there with the hotkey and shows the live activity from the top edge.
- The Show Perch on menu ends with a Hover opens on external displays switch (`Prefs.hoverExternal`, off by default, shown only while such a display is connected) that lets the top edge open it too.

## The notch itself

- The resting notch on a Mac with one is drawn a point inside the size the system reports, with smooth corners (app.js `notchPath`), so it hides behind the hardware.
- `PERCH_NOTCH_GUIDE=1` paints it magenta at the full reported size to see any overhang.
