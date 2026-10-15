<!--
Written for two readers: the owner deciding whether to merge, and an agent reviewing or picking this up later.
Plain words, sentence case, what the user sees first. Delete a section's comment once it is filled; write "None" rather
than deleting a section. Agents: see "Opening a PR" in AGENTS.md (or the open-pr skill), which fills all of this.
-->

## What changes

<!-- Two or three sentences in the user's terms: what someone using Perch notices. Then why, if it is not obvious. -->

## Demo

<!-- ./scripts/pr-demo.sh --publish fills this between the markers: a GIF, the MP4, and a still of each changed
scenario with what it shows. No visible change: replace the markers with "No visible change." -->
<!-- demo -->
<!-- /demo -->

## What's new, changed, removed

<!-- One line per behaviour, as the user meets it. Name the key or the setting. -->
- New:
- Changed:
- Removed:

## Try it

<!-- Where a reviewer looks with their own eyes. -->
- Design page: <!-- scenario names, as Group/Name -->
- In the app: <!-- e.g. ./scripts/run.sh --show, --activity, --onboarding; what to press -->

## Where in the code

<!-- The few files that matter and what each change does there, so a reviewer reads them in the right order. -->
- 

## Risk and what was not checked

<!-- Anything that touches: hooks or other apps' config (HookInstaller), Accessibility or the keyboard (cardTakesKeys,
makeWay), the Claude app's page (ClaudeComposer), the panel's size (cards fit its 410 pt), updates (Sparkle).
Say plainly what you did not try. -->

## Checks

- [ ] `swift test` passes (count: )
- [ ] Looked at every changed state in the design page
- [ ] `ui/app.js` is ASCII only, CSS rebuilt (`cd ui && npm run build`)
- [ ] Settings and onboarding cards fit the 440 pt panel (if a row was added)
- [ ] AGENTS.md or its `docs/behavior/` file updated where behaviour or structure changed
- [ ] Release notes and version (only for a release)
