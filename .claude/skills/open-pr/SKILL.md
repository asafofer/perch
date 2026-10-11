---
name: open-pr
description: Open a pull request in Perch with the filled PR template and a demo (GIF, MP4, stills) filmed from the design page. Use whenever asked to open, create or update a PR in this repo, or to (re)generate a PR's demo.
---

# Opening a PR in Perch

Every PR is read by the owner deciding whether to merge and by agents reviewing it later. The body follows
`.github/pull_request_template.md`; a hook (`.claude/hooks/pr-body-check.py`) refuses `gh pr create` without it.

1. **Ready.** Work committed (one-line messages, no AI or co-author mention), `swift test` green, branch pushed.
2. **Which scenarios show it.** `git diff --stat origin/main...HEAD`. A visible change has scenarios in `ui/design.html`
   (AGENTS.md: design page first). `./scripts/pr-demo.sh --list` lists them all. With no argument the script films the
   scenarios whose lines changed; if the change shows in scenarios that did not change (an `app.js` fix), name them.
   No visible change (Swift logic, scripts): no demo, write "No visible change." in Demo.
3. **Film it locally first.** `./scripts/pr-demo.sh [names...]` writes `build/pr-demo/`. Look at the stills (Read the
   PNGs) and check each shows what it claims: a still that caught a transition or an empty desk means a longer
   `--hold` or a different scenario. It films headless; if it fails, say so and open the PR anyway.
4. **Write the body** to a scratch file from the template, every section filled from the diff, not from memory:
   - What changes: what a user notices, in two or three sentences.
   - What's new, changed, removed: one line per behaviour, naming keys and settings.
   - Try it: the design page scenarios (Group/Name) and the `./scripts/run.sh` flag to see it in the app.
   - Where in the code: the files that matter, in reading order, and what changed in each.
   - Risk and what was not checked: plainly, including anything only checked in the design page and not the app.
   - Checks: tick only what you ran; give the test count.
   - Leave `<!-- demo -->` and `<!-- /demo -->` in place; the script fills between them.
   End the body with the attribution line the session asks for, if any.
5. **Open it:** `gh pr create --title "<sentence-case title>" --body-file <file>` (the hook checks the body).
6. **Publish the demo:** `./scripts/pr-demo.sh --publish [names...]`. It pushes the media to the `pr-media` branch
   (never main) and writes the Demo section into the PR. Open the PR page and check the GIF and stills render.
7. Later commits that change what is shown: run step 6 again; it replaces that PR's media and Demo section.
