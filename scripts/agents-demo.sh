#!/bin/bash
# A live setup for trying Perch with the other agents and multiplexers, in your own terminal:
#   - a herdr session "perch-demo" with pi, OpenCode, Claude Code and Codex side by side in the folder you pass
#     (this repo by default), shown in a new cmux workspace;
#   - pi on its own in a second cmux workspace, so you can compare a cmux split with a herdr pane.
# Each agent gets one small read-only question, so it has a session for Perch to show.
# Needs herdr, cmux, pi, opencode, claude and codex. Run it again to start over; `herdr session stop perch-demo` ends it.
set -euo pipefail
cd "$(dirname "$0")/.."
DIR=$(cd "${1:-.}" && pwd)
NAME=perch-demo
export HERDR_SOCKET_PATH="$HOME/.config/herdr/sessions/$NAME/herdr.sock"
pick() { python3 -c "import json,sys; print(json.load(sys.stdin)$1)"; }
quote() { printf '%q' "$1"; }

for tool in herdr pi opencode claude codex; do command -v "$tool" >/dev/null || { echo "$tool is not installed"; exit 1; }; done
[ -d /Applications/cmux.app ] || { echo "cmux is not installed"; exit 1; }

# A fresh herdr server for the demo.
herdr session stop "$NAME" >/dev/null 2>&1 || true
(cd /tmp && exec herdr --session "$NAME" server) </dev/null >/dev/null 2>&1 &
disown
for _ in $(seq 50); do herdr workspace list >/dev/null 2>&1 && break; sleep 0.2; done

# Four panes: pi and OpenCode on top, Claude Code and Codex below.
P1=$(herdr workspace create --cwd "$DIR" --label "Perch demo" --no-focus | pick "['result']['root_pane']['pane_id']")
P2=$(herdr pane split "$P1" --direction right --cwd "$DIR" --no-focus | pick "['result']['pane']['pane_id']")
P3=$(herdr pane split "$P1" --direction down --cwd "$DIR" --no-focus | pick "['result']['pane']['pane_id']")
P4=$(herdr pane split "$P2" --direction down --cwd "$DIR" --no-focus | pick "['result']['pane']['pane_id']")
echo "Starting the agents in herdr..."
herdr agent start demo-pi --kind pi --pane "$P1" >/dev/null || true
herdr agent start demo-opencode --kind opencode --pane "$P2" >/dev/null || true
herdr agent start demo-claude --kind claude --pane "$P3" >/dev/null || true
herdr agent start demo-codex --kind codex --pane "$P4" >/dev/null || true
sleep 2
herdr agent prompt demo-pi "Read README.md and tell me in two sentences what this project does. Do not edit anything." >/dev/null || echo "pi is not ready: answer it in its pane"
herdr agent prompt demo-opencode "List the files in Sources/PerchCore and say in one sentence which one reads pi sessions. Do not edit anything." >/dev/null || echo "OpenCode is not ready: answer it in its pane"
herdr agent prompt demo-claude "Run git log --oneline -5 and sum up the last five commits in one line each. Do not edit anything." >/dev/null || echo "Claude Code is not ready: answer it in its pane"
herdr agent prompt demo-codex "Read Package.swift and tell me in one sentence which macOS version it targets. Do not edit anything." >/dev/null || echo "Codex is not ready: answer it in its pane"

# cmux: herdr in one workspace, pi on its own in another. cmux's own tool only answers processes inside cmux, so this
# goes through AppleScript; text goes in as a paste, and Return is sent on its own.
HERDR_CMD="herdr --session $NAME"
PI_CMD="cd $(quote "$DIR") && pi $(quote "Read Package.swift and tell me in one sentence which Swift tools version it uses. Do not edit anything.")"
osascript - "$HERDR_CMD" "$PI_CMD" <<'EOF'
on run argv
  tell application "cmux"
    activate
    delay 1
    set a to new tab
    select tab a
    delay 1
    input text (item 2 of argv) to focused terminal of a
    delay 0.2
    perform action "text:\\r" on focused terminal of a
    set h to new tab
    select tab h
    delay 1
    input text (item 1 of argv) to focused terminal of h
    delay 0.2
    perform action "text:\\r" on focused terminal of h
  end tell
end run
EOF
echo "Ready: herdr ($NAME) and pi are open in cmux. Perch lists their sessions within a few seconds."
