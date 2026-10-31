---
name: add-provider
description: Connect a new provider to Perch (an agent, an app sessions run in, or a terminal host) and test it. Use when asked to support, add, spike or check a new agent, app or terminal, or to say what one can do.
---

# Adding a provider

A provider earns a row in [providers.md](../../../docs/behavior/providers.md). That row is the contract: every cell ends as ✓,
~ with its limit, ✗ with the reason, or — . Work in three stages, each finished before the next: **spike**, **design**, **build**.

## 1. Spike: what is possible

Install the real tool and drive it; a stand-in or the docs alone tell you what should happen, not what does. Ask the owner
before installing or signing in. Write `docs/spikes/<provider>.md` in the shape of [cursor.md](../../../docs/spikes/cursor.md):
date, version, bundle id and URL scheme, **In short**, then the evidence.

Answer each question with what you saw, or say it was not driven:

- **Sessions.** Where they live (files, SQLite, an app's cache), the id, title, folder, times, and how archived, subagent and
  headless ones are told apart. Read databases read-only; take only the keys you need from anything holding secrets.
- **Words.** The user's prompts, the agent's replies, tool calls and results, and how a turn ends.
- **Status.** Hooks, plugin or extension events, or a state field; which say started, tool ran, waiting on you, finished.
- **Approvals and questions.** Does it ask? Can an answer go back (hook reply, its client or API, a window through
  Accessibility)? Does holding a request block the tool's own prompt?
- **Reply.** A terminal it runs in, an app window, a link with your words.
- **Pick up.** A link or command that opens the exact session; the resume command.
- **Running.** How its process looks in the process table (executable, argv[0]), for `Agent.recognise`.
- **New session.** A command or link that starts one in a chosen folder with a prompt.
- **Pull requests.** Do tool results with the `gh pr create` address reach its log?

Done when every column of the provider's row has a verified answer, and the spike's **In short** says which are ✓, ~ and ✗.

## 2. Design: the visible part

New UI goes in `ui/design.html` first (AGENTS.md, step 1): the name in `AGENTS` and its kind in `KINDS` (app.js), its real
icon (the app's own, read into `ui/icons.local.json` by `--design-icons`; a published mark in `MARKS` when it has no app),
a sample session in the dev harness, and scenarios for each status it can reach. Open the page for the owner and wait for
"build it".

## 3. Build: wire and test

Follow the nearest existing provider and touch only what its row needs:

| Piece | Where |
|---|---|
| Identity, resume, answers from the notch, process | `Agent.swift` (`all`, `recognise`, `mayBe`) |
| Reading sessions | a store beside `OpenCode.swift`, `Pi.swift`, `Cursor.swift`; a scanner in `SessionScan.swift`; `RealSessionProvider` |
| Words and status from the log | `Transcript.swift` (`SessionDigest`), `Recap` |
| Live status, approvals, questions | `LiveStatus.swift`, `HookServer.agents`, `HookInstaller` (and `PerchPlugins` for a plugin file) |
| Pick up, reply | `Terminals.swift`, or a window driver like `CursorWindow.swift`, `ConductorApp.swift` |
| New session | `NewSession.swift`, `NewSessionStarter.swift` |
| Icon | `AppIcons.apps` (bundle id) |
| Pull requests | `PullRequestScan` for its log |

Tests, in this order:

1. **Unit:** a fake home with real files from the spike (`OtherAgentsScanTests`, `CursorScanTests`), and `LiveStatusTests`
   for its events. `swift test` stays green.
2. **Hooks in a stand-in home** before your real config: `PERCH_HOME=<short folder> .build/debug/Perch --install-hooks <id>`,
   then the tool run with only that home. Raise a request by hand through the socket:
   `echo '<payload>' | ~/.config/perch/hook <id> <event>` ([status.md](../../../docs/behavior/status.md#trying-it)).
3. **The real app with the real tool** (AGENTS.md, step 2), driving each ✓ cell: the session is listed with its words; status
   moves from working to finished; an approval and a question answered from the notch land in the tool; a reply arrives;
   Pick up reaches the exact session; New session starts one in the chosen folder; a pull request it opened shows. Follow
   the driving rules in memory (drive banner, `screencapture` for the panel).

Done when `swift test` passes, every ✓ in the row was driven in the real app, and the PR says what was driven and what was not.

## Docs

The same PR fills the provider's row in providers.md (replacing its "design only" line), its own section in `sessions.md`
or `agents.md`, its status notes in `status.md`, and its name in AGENTS.md's opening paragraph.
