# Show Perch on: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Settings choice, Show Perch on (screen with mouse, screen with active window, or a named display), decides where the shortcut opens Perch and where Perch shows up by itself. Hovering the top of any eligible screen still opens it there.

**Architecture:** Two pure pieces go in `PerchCore`, where they are tested: a `ShowOn` choice and `ScreenTarget`, which picks a screen index from frames, the mouse and the front window. The AppKit shell supplies the real inputs: display UUIDs, the front window from `CGWindowList`, and the preference. `NotchController` asks for the target screen where it used to ask for the cursor's screen, except on a hover. The page side is already built and committed (`ui/app.js`: `showHtml`, `bindShow`, `showMenu`). This plan only feeds it.

**Tech Stack:** Swift 6.2, AppKit, CoreGraphics, Swift Testing (`import Testing`, `@Test`, `#expect`), plain JS UI.

**Spec:** `docs/superpowers/specs/2026-10-11-show-perch-on-design.md`

## Global Constraints

- "Screen with mouse" behaves exactly as Perch does today: same `mouseMoved` follow, same hover, same placement.
- Preference values: key `showOn`, raw values `"mouse"` (default, and anything unknown), `"window"`, or a display's UUID string. Key `showOnName` holds the chosen display's name, for when it is not connected.
- Snapshot fields the page reads in `settings`: `showOn: String`, `displays: [{id: String, name: String, connected: Bool}]`, plus the existing `hasExternal` and `hoverExternal`.
- The page posts `{type: "setting", key: "showOn", value: String}`, and the existing `{type: "setting", key: "hoverExternal", value: Bool}`.
- No new permissions. Perch never takes the keyboard when it opens by itself.
- Commits: one-line messages, no mention of AI or co-authors (AGENTS.md). Commit after every working step. `swift test` stays green.
- `ui/app.js` stays ASCII-only: `python3 -c "print(all(ord(c)<128 for c in open('ui/app.js').read()))"` prints `True`.

## Review Focus

1. **The chosen display is unplugged while wings show:** the panel moves to the mouse's screen. Plugging the display back in puts the panel back on it (`didChangeScreenParametersNotification`). Task 3, step 7.
2. **Active-window mode with no usable front window** (the desktop focused, an app with no windows, Perch's own panel frontmost): Perch follows the mouse and does not land on a random screen. Task 1 test `windowModeWithNoWindowFollowsMouse`, plus Task 2's filter on Perch's own process ID.
3. **Fixed mode, hovering another screen's top while an activity shows on the target, then leaving:** the panel goes back to the target, and the activity is drawn there again. Task 3, step 7.
4. **A display stacked above the target:** the hover zone reaches above a screen's edge, so it only counts when the cursor is on that screen itself. Task 1 test `hoverZoneNeedsTheCursorOnThatScreen`.
5. **A display with no UUID** (some virtual or AirPlay displays): it still gets a stable ID and a menu entry. Task 2 uses `"id:<CGDirectDisplayID>"` as the fallback, checked by eye in Task 2, step 4.

---

### Task 1: Pure screen choice in PerchCore

**Files:**
- Create: `Sources/PerchCore/ScreenTarget.swift`
- Modify: `Sources/PerchCore/NotchGeometry.swift` (add `hoverRect`)
- Test: `Tests/PerchCoreTests/ScreenTargetTests.swift`

**Interfaces:**
- Produces:
  - `public enum ShowOn: Equatable, Sendable { case mouse, window, display(String) }` with `public init(raw: String)` (`"mouse"` or unknown → `.mouse`, `"window"` → `.window`, empty → `.mouse`, anything else → `.display(raw)`) and `public var raw: String`.
  - `public enum ScreenTarget`, with `public static func index(for choice: ShowOn, displayIDs: [String], frames: [CGRect], mouse: CGPoint, window: CGRect?) -> Int?`. `.mouse` gives `ScreenPicker.index(of: mouse, in: frames)`. `.window` gives the frame with the largest intersection area with `window`; with a nil window or no overlap, it falls back to the mouse. `.display(id)` gives `displayIDs.firstIndex(of: id)`, falling back to the mouse when missing. It returns nil only when the mouse fallback finds nothing.
  - `public static func cocoaRect(fromCG r: CGRect, primaryHeight: CGFloat) -> CGRect` on `ScreenTarget`: CoreGraphics global coordinates (origin top-left of the primary display) to Cocoa (origin bottom-left). The result is `CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)`.
  - `public static func hoverRect(for screen: ScreenInfo, wingsWidth: CGFloat = 0) -> CGRect` on `NotchGeometry`: the body of today's `NotchController.notchHoverRect()`, moved here unchanged. It is `w = max(idle.width, 150, wingsWidth)`, left 30, right 8, `y = maxY - idle.height - 2`, `height = idle.height + 40`.
  - `public static func hovering(_ p: CGPoint, frames: [CGRect], index i: Int, rect: CGRect) -> Bool` on `NotchGeometry`: `rect.contains(p) && ScreenPicker.index(of: p, in: frames) == i`.

- [ ] **Step 1: Write the failing tests** in `ScreenTargetTests.swift` (`@Suite struct ScreenTargetTests`). Fixtures: `laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)`, `lg = CGRect(x: 1512, y: 0, width: 2560, height: 1440)`, `frames = [laptop, lg]`, `ids = ["A", "B"]`.
  - `rawRoundTrips`: `ShowOn(raw: "mouse") == .mouse`, `ShowOn(raw: "window") == .window`, `ShowOn(raw: "B") == .display("B")`, `ShowOn(raw: "") == .mouse`, and `ShowOn.display("B").raw == "B"`.
  - `mouseModeFollowsTheCursor`: mouse `(2000, 500)` gives `1`. Mouse `(700, 982)` (resting on the laptop's top edge) gives `0`.
  - `windowModePicksTheScreenHoldingMostOfIt`: a window `CGRect(x: 1400, y: 100, width: 800, height: 600)` with the mouse on the laptop gives `1`.
  - `windowModeWithNoWindowFollowsMouse`: a nil window with the mouse `(100, 100)` gives `0`. A window `CGRect(x: 9000, y: 9000, width: 10, height: 10)` with the mouse `(2000, 500)` gives `1`.
  - `displayModeIgnoresTheMouse`: `.display("A")` with the mouse `(2000, 500)` gives `0`.
  - `missingDisplayFollowsMouse`: `.display("Z")` with the mouse `(2000, 500)` gives `1`.
  - `mouseOffEveryScreenIsNil`: `.mouse` with the mouse `(-500, -500)` gives `nil`.
  - `cocoaRectFlipsY`: `cocoaRect(fromCG: CGRect(x: 100, y: 50, width: 400, height: 300), primaryHeight: 982) == CGRect(x: 100, y: 632, width: 400, height: 300)`.
  - `hoverRectMatchesTheOldZone`: for the notched `ScreenInfo(frame: laptop, notchSize: CGSize(width: 185, height: 32))`, `hoverRect == CGRect(x: 633.5, y: 948, width: 223, height: 72)`.
  - `hoverZoneNeedsTheCursorOnThatScreen`: `top = CGRect(x: 0, y: 982, width: 1512, height: 982)` stacked above the laptop. With `frames2 = [laptop, top]` and the laptop's hover rect, the point `(756, 990)` gives `hovering(..., index: 0, ...) == false`, and `(756, 970)` gives `true`.
- [ ] **Step 2: Run them and see them fail**
  Run: `swift test --filter ScreenTargetTests`
  Expected: it fails to compile, with `cannot find 'ShowOn' in scope`.
- [ ] **Step 3: Implement** `ShowOn` and `ScreenTarget` in `ScreenTarget.swift`, and `hoverRect` and `hovering` in `NotchGeometry.swift`, to the Interfaces above. The window overlap is `frame.intersection(window)`, with area `width * height`. A null intersection counts as 0. Ties go to the lower index.
- [ ] **Step 4: Run them and see them pass**
  Run: `swift test --filter ScreenTargetTests`, then `swift test`.
  Expected: all pass, 195 + 10 tests.
- [ ] **Step 5: Commit**
  `git add Sources/PerchCore/ScreenTarget.swift Sources/PerchCore/NotchGeometry.swift Tests/PerchCoreTests/ScreenTargetTests.swift && git commit -m "ShowOn and ScreenTarget: which screen Perch opens on, tested"`

### Task 2: Real displays, the front window and the preference

**Files:**
- Modify: `Sources/Perch/ScreenSupport.swift`
- Modify: `Sources/Perch/Preferences.swift`
- Modify: `Sources/Perch/main.swift` (`--dump` prints the screens)

**Interfaces:**
- Consumes: `ShowOn`, `ScreenTarget.index`, `ScreenTarget.cocoaRect` (Task 1).
- Produces:
  - `Prefs.showOn: ShowOn` (key `"showOn"`, stored as `.raw`, default `.mouse`) and `Prefs.showOnName: String?` (key `"showOnName"`).
  - `extension NSScreen { var displayID: String }`: the UUID string from `CGDisplayCreateUUIDFromDisplayID(deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as CGDirectDisplayID)`, else `"id:\(number)"`.
  - `enum FrontWindow { static func frame() -> CGRect? }`: the first entry of `CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)` whose `kCGWindowOwnerPID` is `NSWorkspace.shared.frontmostApplication?.processIdentifier` (and not Perch's own process ID), `kCGWindowLayer == 0`, and bounds at least 50×50. Converted with `ScreenTarget.cocoaRect(primaryHeight: NSScreen.screens[0].frame.height)`. Nil otherwise.
  - `ScreenChooser.target() -> NSScreen`: `ScreenTarget.index(for: Prefs.showOn, displayIDs: screens.map(\.displayID), frames: screens.map(\.frame), mouse: NSEvent.mouseLocation, window: Prefs.showOn == .window ? FrontWindow.frame() : nil)`, else the same fallback as `current()`.
  - `ScreenChooser.rest() -> NSScreen`: `Prefs.showOn == .mouse ? current() : target()`. This is where the panel sits while nothing is open.

- [ ] **Step 1: Add** `Prefs.showOn` and `Prefs.showOnName` next to `hoverExternal`, with a doc comment in the file's voice.
- [ ] **Step 2: Add** `NSScreen.displayID`, `FrontWindow` and `ScreenChooser.target()` / `rest()` to `ScreenSupport.swift`.
- [ ] **Step 3: Extend `--dump`** in `main.swift`. Before the sessions, print one line per screen, `screen: <localizedName> | <displayID> | notch: yes/no`, then `show on: <Prefs.showOn.raw> -> <ScreenChooser.target().localizedName>`.
- [ ] **Step 4: Verify on the real machine**
  Run: `./scripts/run.sh` once (it builds `build/Perch.app`, bundle id `app.perch.mac`), quit Perch, then `build/Perch.app/Contents/MacOS/Perch --dump | head -5`.
  Expected: each connected display listed with a UUID (or `id:` for one without), and `show on: mouse -> <the screen the cursor is on>`.
  Then `defaults write app.perch.mac showOn window`, put a window on the other screen and focus it, and re-run. Expected: `-> <that screen>`. Reset with `defaults delete app.perch.mac showOn`.
- [ ] **Step 5: Commit**
  `git add Sources/Perch/ScreenSupport.swift Sources/Perch/Preferences.swift Sources/Perch/main.swift && git commit -m "Display IDs, the front window and the Show Perch on preference"`

### Task 3: NotchController uses the target, Settings feeds the page, docs

**Files:**
- Modify: `Sources/Perch/NotchController.swift`
- Modify: `Sources/Perch/Snapshot.swift` (`Settings` gains `showOn`, `displays`)
- Modify: `AGENTS.md` (Displays paragraph, Architecture lines for `ScreenTarget`)

**Interfaces:**
- Consumes: `ScreenChooser.target()`, `ScreenChooser.rest()`, `NSScreen.displayID`, `Prefs.showOn`, `Prefs.showOnName` (Task 2), and `NotchGeometry.hoverRect` / `hovering` (Task 1).
- Produces: `UISnapshot.Settings.showOn: String`, `UISnapshot.Settings.displays: [UISnapshot.Display]`, where `struct Display: Encodable { let id: String; let name: String; let connected: Bool }`.

- [ ] **Step 1: Placement.** In `prepareToShow()`, use `openedByHover ? ScreenChooser.current() : ScreenChooser.target()`. The callers already set `openedByHover` first (`comeBack`, `reopen`, `toggleSwitcher`). The `"settings"` message handler and `startOnboarding` use `target()`. The return to idle after a dismiss (the `Task` that sleeps 700 ms) and the `didChangeScreenParametersNotification` observer use `rest()`. The observer also calls `push()` while in `.settings`, so the display list updates live.
- [ ] **Step 2: Hover in a fixed mode.** `notchHoverRect()` becomes `NotchGeometry.hoverRect(for: info, wingsWidth: activityMode == "wings" ? activitySize.width : 0)`. In `mouseMoved()` while idle, keep today's line when `Prefs.showOn == .mouse`. Otherwise:
  - Find the screen under the cursor.
  - If it isn't the panel's screen, is eligible (`notchSize != nil || Prefs.hoverExternal`), and `NotchGeometry.hovering(at, frames:, index:, rect: NotchGeometry.hoverRect(for: that.screenInfo))` holds, then `place(on:)` it and `push()`.
  - Else, if the panel is not on `rest()`, the cursor is outside `notchHoverRect()`, and no `hoverTask` is pending, then `place(on: ScreenChooser.rest())` and `push()`. Call `rest()` only on that branch, since in window mode it reads the window list.
- [ ] **Step 3: Window mode follows app switches.** In the existing `didActivateApplicationNotification` observer (around line 567), when `Prefs.showOn == .window` and `machine.phase == .idle`, call `place(on: ScreenChooser.rest())` and `push()` if the screen changed.
- [ ] **Step 4: Settings state and the message.**
  - `settingsState()` passes `showOn: Prefs.showOn.raw` and `displays`: `NSScreen.screens` mapped to `Display(id: displayID, name: localizedName, connected: true)`, plus `Display(id: id, name: Prefs.showOnName ?? "Display", connected: false)` when `Prefs.showOn` is `.display(id)` and no screen has that ID.
  - In the `"setting"` case, `key == "showOn"`, with a String value, sets `Prefs.showOn = ShowOn(raw:)` and sets `Prefs.showOnName` to the matching screen's `localizedName` (nil for mouse or window).
  - `hoverExternal` is already handled. Nothing changes there.
- [ ] **Step 5: Build, test, check the page side.**
  Run: `swift build && swift test`, then `python3 -c "print(all(ord(c)<128 for c in open('ui/app.js').read()))"`.
  Expected: build complete, all tests pass, `True`.
- [ ] **Step 6: Commit**
  `git add Sources/Perch/NotchController.swift Sources/Perch/Snapshot.swift && git commit -m "Show Perch on: the shortcut and what Perch shows by itself open on the chosen screen"`
- [ ] **Step 7: Verify in the real app**, with the laptop and an external display. Run `./scripts/run.sh` and use `PERCH_TRACE=1`, whose `Perch screen:` lines show every move. Check each of these and write down what you saw:
  - **Mouse mode:** the shortcut opens on the cursor's screen. Hovering the notch opens it as today.
  - **Built-in display chosen, cursor on the external:** the shortcut opens on the laptop. `./scripts/run.sh --activity` plays the activity on the laptop. Hovering the external's top, with Hover opens on, opens there. Moving away puts the resting notch back on the laptop.
  - **Window mode:** focus a window on the external, then press the shortcut. Perch opens on the external. Click the desktop on the laptop (no window), then press the shortcut. Perch opens on the cursor's screen.
  - **Unplugging:** with the external chosen, unplug it. The panel moves to the cursor's screen, and Settings shows the external greyed as "Not connected", still checked. Plug it back in, and the resting notch returns to it.
  - **The setting itself:** with Hover opens on external displays switched in the menu, the switch slides, the menu stays open, and the setting sticks after relaunching.
  - Capture the panel with `screencapture -x -R 496,0,520,340 out.png` (computer-use screenshots hide it).
- [ ] **Step 8: Docs.** In `AGENTS.md`:
  - Rewrite the Displays paragraph: Show Perch on (`Prefs.showOn`, `ScreenChooser.target()` / `rest()`, `ScreenTarget` in PerchCore), hover still opening on the hovered screen, and the Hover opens switch now living at the end of that menu.
  - Add `ScreenTarget` to the PerchCore list in Architecture.
  - Commit: `git add AGENTS.md && git commit -m "AGENTS: Show Perch on"`
