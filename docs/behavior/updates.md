# Updates: Sparkle, signing, What's new, Accessibility after an update

## How Perch updates

- Perch updates itself with Sparkle (`Sources/Perch/Updater.swift`). Cutting a release is the owner's, with tooling kept outside this repo.
- `SUFeedURL` in `Resources/Info.plist` points at `appcast.xml` in the public repo `asafofer/perch-releases` (the source repo, `asafofer/perch`, is public too, MIT); the zips are that repo's release assets.
- Each update is signed with an EdDSA key (public half `SUPublicEDKey` in the plist; the private half never leaves the owner's Mac), so only the owner can publish an update installed copies accept.
- It checks every hour (`SUScheduledCheckInterval`, Sparkle's shortest), and again when the Mac wakes or you come back from a break (`Updater.checkSoon`, at most every 15 minutes).
- Nothing downloads until you press Update; once you do, a downloaded update restarts Perch only when `NotchController.isQuiet` (nothing open, no draft).
- A test build (`PerchTestBuild`) and any `--fake`, `--demo` or `--snapshot` run never update.
- Sparkle's version compare uses the build number, the commit count, so a release must be cut from a commit newer than the last.

## Signing

- A release build (`CONFIG=release ./scripts/run.sh`) is signed with a Developer ID certificate when the Mac has one, with the hardened runtime and `Resources/Perch.entitlements` (Apple Events, for the AppleScript that drives Terminal, iTerm2 and cmux).
- Test builds (`run.sh`) are signed with the Developer ID certificate when the Mac has one, without the hardened runtime and timestamp. A test build signed another way than the installed Perch took its permissions over (Documents, Accessibility) each time one or the other ran, so macOS asked again after every Allow. Without Developer ID they use the self-signed "Perch Dev" certificate and no hardened runtime: that certificate has no team, and the hardened runtime then refuses to load Sparkle.
- Every release must be signed with the same Developer ID certificate, otherwise macOS asks for Accessibility again after the update (the move from "Perch Dev" to Developer ID does this once). How Perch says so: [Accessibility lost after an update](#accessibility-lost-after-an-update).

## Perch's own face

- The update has Perch's own face, not Sparkle's windows: `Updater` is Sparkle's user driver, and the page draws it (app.js, "an update of Perch itself"). The design page's Updates tab plays every state; `./scripts/run.sh --update-demo` plays it over the real notch.
- A check on the schedule that finds an update holds Sparkle's offer and peeks once per version (`UpdateInfo.peek`, app.js `peek` mode): at a quiet moment the notch grows to one line, Update available and the version with a blue download mark, for four seconds; a request waiting on you goes first. A click opens it into the offer row.
- The page posts `peeked` as it shows, and the version is kept (`update.peeked`), so later checks and restarts leave the notch empty (`listOnly`, also set while a Not now holds). Sparkle runs no scheduled check while an offer is held.
- Check for updates in the menu opens the offer row (Update, Later, What's new); with an offer already held it shows that one again, as the row.
- Later puts the row away and keeps the offer: the list and cards keep a blue chip at their top right (Update, the ring while it downloads, Restart) until you update.
- Pressing Update downloads it (the ring beside the camera), then restarts at a quiet moment ("Updating", then a small "Updated" row).
- The buttons have no keys: the notch never takes the keyboard when it opens by itself.

## What's new

- After an update, the first start on the new version opens a What's new card instead of the small Updated row (`NotchPhase.whatsNew`, app.js `whatsNew`, the design page's Updates tab).
- It shows the version, the release's headline and its lines, in the inset box the expanded reply uses, with the same fade when it scrolls.
- The notes are `release-notes/<version>.md`: a headline line, then `- ` lines (any number; six show and the rest scroll). The appcast embeds the same file, `run.sh` copies it into the app's Resources, and `UpdateNotes.bundled` reads it. A release with no notes keeps the small row.
- It opened by itself, so it takes no keyboard. Got it is a click or Command+Option+Return (`onWhatsNewKey`, registered only while the card shows) and goes on to the list; the shortcut that opens Perch does too. The close puts Perch away.
- It waits for a quiet moment (nothing on the notch, no call) and shows once per version.
- `./scripts/run.sh --whats-new` plays it over the real notch.

## When an update does not go through

- The row says why and what to do instead of a bare "Couldn't check". `UpdateProblem.classify` (PerchCore, tested) reads Sparkle's error and the ones inside it (a download that failed offline carries the network's error) into a notch line, a few words for Settings, and a fix:
  - Try again;
  - Show in Finder, for Perch running from Downloads or a folder it cannot write to: macOS runs a downloaded app from a read-only copy that nothing can replace (`SURunningTranslocated`), and Show in Finder reveals where it was unzipped;
  - or nothing.
- A Mac that cannot run the newest release (Intel, or macOS too old) is told so rather than "up to date" (`UpdateProblem.noUpdate`).
- Only a check you asked for or an update already on its way says it failed; a failed scheduled check stays quiet.
- Perch still here 20 s after the restart began says it could not quit, and Try again asks Sparkle to quit it once more.
- The design page's Update errors category plays every case, in the notch and in Settings.

## Accessibility lost after an update

- macOS ties Accessibility to the code signature, so an update signed another way (the move to Developer ID) drops it without a word.
- Perch reads it every two seconds and remembers it had it (`AccessLoss`, `Prefs.accessHad`, `accessHadOn` the build that last had it, `accessSaid`), and says once per loss that it is gone:
  - on the update's own What's new card when the build changed (`whatsNew.access`, app.js `wnAccess`);
  - otherwise in a notch row at a quiet moment, after the first six seconds and after What's new (`access` in the snapshot, app.js `renderAccess`), with Later and Allow for the mouse.
- Allow is Settings' own (`onboardingAction("accessibility")`: tccutil reset, then ask). macOS's own prompt opens the pane, and only answering it lists Perch there, so Perch never opens the pane itself. The row waits for the switch, then says Allowed.
- While What's new asks for it, a press outside (the click in System Settings that turns the switch on) or another app coming forward does not close the card (`wnHoldsForAccess`), so it turns green. Got it and its close still close it.
- Settings' row says needs access again in orange. The design page's Accessibility category plays every state.
- An install from before `access.had` was kept counts, once set up, as having had it on an earlier build (`AccessLoss.seeded`), so the first update signed another way is said on What's new.
- To try that path: quit Perch, `defaults delete app.perch.mac access.had; defaults delete app.perch.mac access.hadOn; defaults delete app.perch.mac access.said`, turn Perch off in System Settings, then `./scripts/run.sh --whats-new`.

## Testing an update without publishing

Build two copies with different `CFBundleVersion` and a `SUFeedURL` on localhost, serve a folder with `generate_appcast` output, and launch the older copy outside /Applications.
