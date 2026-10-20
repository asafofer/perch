# Contributing to Perch

Thanks for wanting to help. Perch is small on purpose: the bar is polish and restraint, not more features. A bug fix or a rough edge smoothed is the easiest thing to land. For a new feature, open an issue first and say what it is for, so nobody builds something that will not be merged.

[AGENTS.md](AGENTS.md) is the full guide, for people and coding agents alike: architecture, design rules and the things that will bite you. Read it before a change of any size, and the file in [docs/behavior](docs/behavior) for the area you change.

## Set up

Perch runs on macOS 15 (Sequoia) or later. To build it you need a Mac on Apple silicon with Xcode 26 or later (Swift 6.2) and Node 20 or later.

```bash
cd ui && npm install && cd ..       # once
./scripts/make-dev-cert.sh          # once: a stable signing identity, so macOS keeps Perch's permissions across builds
git config core.hooksPath .githooks # once: runs the tests before every push
./scripts/run.sh --show             # build, launch, open the card
swift test
```

## How a change goes in

1. **Design page first.** Anything you can see goes into `ui/design.html` (the real interface with sample data) as a scenario, and is looked at there before it is built into the app. Serve it with `cd ui && python3 -m http.server 8765` and open `/design.html`.
2. **Follow the design rules** in AGENTS.md: Inter, sentence case, small type, no dividing lines, no glowing dots, real app icons, and Perch never takes the keyboard when it opens by itself.
3. **Keep `ui/app.js` ASCII only** (write other characters as `\uXXXX`) and rebuild the CSS after adding Tailwind classes: `cd ui && npm run build`, and commit `ui/dist/ui.css`.
4. **Commits:** one line each, saying what changed.
5. **Open a pull request** against `main`. Its description follows the template GitHub fills in: what changes, a demo, what is new, how to try it, where in the code, risks, checks. For a visible change, film the demo with `./scripts/pr-demo.sh` (needs ffmpeg) and attach `build/pr-demo/demo.gif`; with no visible change, write "No visible change." in Demo.

## What CI checks

Every pull request runs:

- **Tests:** `swift test` on macOS 26. The app targets macOS 15, so an API newer than that needs an `if #available` check with a fallback.
- **UI:** `ui/app.js` is ASCII only, the scripts parse, and the committed `ui/dist/ui.css` matches a fresh build.
- **PR description:** it follows the template.

All three must pass before a pull request can be merged.

## Reporting a bug

Use the bug report form in Issues. A security problem goes through [SECURITY.md](SECURITY.md) instead, not a public issue.

By contributing you agree that your contribution is licensed under the [MIT License](LICENSE).
