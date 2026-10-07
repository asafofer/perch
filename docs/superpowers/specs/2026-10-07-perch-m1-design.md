# Perch, milestone 1: the notch and the bird (fake data)

Reference: [docs/design/mockup.html](../../design/mockup.html). The native app should match its states, sizes and timings.

## Goal

A native macOS app whose whole interface lives in the notch. Milestone 1 proves the interface feels right using fake data. No real sessions, git, AI or window restore yet.

## Out of scope for milestone 1

Reading `~/.claude`, git state, summarizing, Accessibility window restore, first-run onboarding (milestone 2), Windows.

## Stack

Swift 6, SwiftUI for views, AppKit for the window. macOS 26 target (this machine runs 26.6). No third-party dependencies. Direct distribution, not sandboxed.

## Units

| Unit | Job | Depends on |
|---|---|---|
| `PerchApp` | Agent app (`LSUIElement`, no Dock icon, no menu bar item). Owns the panel and hotkeys. | all below |
| `NotchPanel` | Borderless, non-activating `NSPanel` above the menu bar, on every Space. Positions itself from `NSScreen.safeAreaInsets` and `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`. On a Mac without a notch it draws a top-centre pill of the same size. | AppKit |
| `NotchState` | Pure state machine: `idle`, `open`, `switcher`, `restoring`. Takes events (`comeBack`, `next`, `previous`, `confirm`, `dismiss`, `timeout`) and returns the new state. No UI. | none |
| `NotchView` | SwiftUI view for each state, spring-animated between sizes (idle 188x34, open 480x318, switcher 480x296, restoring 480x206). | `NotchState` |
| `BirdView` | The character, drawn in SwiftUI shapes. Moods: sleep, awake (with blink), happy. Perches left of the notch when idle and moves into the card when open. | none |
| `HotkeyService` | Tapping `⌘⌥` together, with no other key, opens the switcher. Detected with a global `flagsChanged` monitor, which needs Accessibility permission. Until that is granted, `⌘⌥Space` (Carbon `RegisterEventHotKey`, no permission) does the same. `⌃⌥Space` simulates "welcome back" for testing. | AppKit, Carbon |
| `SessionProviding` | Protocol returning parked projects (name, branch, away time, goal, decided, next, agent states, restore steps). Milestone 1 ships `FakeSessionProvider` with the three projects from the mockup. | none |

## Behaviour (copied from the mockup)

- Idle: sleeping bird beside the notch, nothing else.
- Welcome back: notch expands with a spring, bird wakes, card shows goal, decided, next, agent states. Auto-collapses after 9 seconds. Hovering pauses the timer. A saffron line at the bottom shows the time left.
- Keys while open: `Return` restores, `Tab` cycles projects, `Esc` dismisses.
- Switcher: list of parked projects. Arrow keys or `Tab` move, `Return` opens, `Esc` closes.
- Restoring: bird is happy and nods twice, three checklist lines tick in, card closes after about 3 seconds. Milestone 1 only shows the checklist and does not move real windows.
- The panel only takes key focus while open. Idle, it never steals focus or intercepts clicks.
- Multiple displays: show on the display that holds the cursor.

## Testing

- Unit tests (XCTest) cover `NotchState` for every state and event, including timeout and hover pause.
- Unit tests cover notch geometry for a notched screen, a plain screen and two displays, using injected screen values.
- Visual check is manual against the mockup: sizes, spring feel, bird moods. Screenshots go in `docs/design/`.

## Done when

You can press `⌃⌥Space` in any app and the notch card appears, behaves as above, and feels like the mockup. The unit tests pass.

## Recap test findings (input to milestone 3)

Three real sessions, last 14 messages each, tool output stripped.

- A large model's recaps were rated right and useful for all three.
- Haiku 4.5 got the goal and decision roughly right, but 2 of 3 "next" lines were stale (one said to merge a branch that was already merged and pushed; one repeated an earlier suggestion the user had overruled).
- So milestone 3 must feed git state (is the branch merged, what is uncommitted) and ask for "what is already done" before "what is next". Start with a Sonnet-class model; try Haiku and a local model later behind the same interface.

## Risks

- Layering above the menu bar and over full-screen apps may need window-level and collection-behavior tuning.
- Spring timing in SwiftUI will not match CSS exactly and needs hand tuning.
