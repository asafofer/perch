# Security

Perch has Accessibility access, reads your coding agents' session files, and can answer an agent's permission request. A flaw in any of that matters, so please report it privately.

## Reporting a vulnerability

Use **Report a vulnerability** on this repository's [Security tab](https://github.com/asafofer/perch/security/advisories/new). It reaches the maintainer only. Please do not open a public issue.

Say what an attacker could do, on which version of Perch (the menu bar menu shows it), and how to reproduce it. You will hear back within a week. A fix ships as an update that installed copies pick up by themselves, and the advisory is published once it is out, with credit to you if you want it.

## What Perch touches

- **Session files** your agents keep on your Mac (`~/.claude`, `~/.codex`, OpenCode's database, pi's sessions), read only.
- **Hooks**, only when Live status is on: one entry in `~/.claude/settings.json` and `~/.codex/hooks.json`, and a plugin file of Perch's own for OpenCode and pi. They talk to Perch over a Unix socket at `~/.config/perch/perch.sock` that only your user can open. A request held there can be allowed, denied or answered from the notch.
- **Accessibility and Automation**, to bring a session forward and type a reply into it.
- **The network**, only to check for and download updates (Sparkle, from GitHub). Each update is signed with an EdDSA key and checked before it installs. Perch sends nothing else anywhere.

The latest release is the one that gets fixes.
