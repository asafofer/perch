#!/bin/bash
# A take for the character-at-the-notch clip: a real Claude Code session that asks to run a harmless command on cue.
#
#   ./scripts/notch-take.sh setup   # once per sitting: the folder, a clean tmux server with Claude Code, a Terminal window on it
#   ./scripts/notch-take.sh ask     # the cue: Claude is asked to run `touch perch-was-here.txt`, which needs your OK
#   ./scripts/notch-take.sh reset   # between takes: Claude's answer cleared, the file removed, ready to ask again
#   ./scripts/notch-take.sh stop    # the tmux server and the Terminal window go
#
# Claude Code runs in a private tmux server started with a clean environment, so it records as a terminal session and not
# as the Claude app (an agent started from this app's terminal inherits its variables). The folder is in ~/PerchTest, since
# Perch skips sessions under /tmp. The command is not on any allow list, so Claude asks, and Perch's hook holds the request
# for the notch. Perch says nothing about the session you are in: after `ask`, keep the Terminal window visible but click
# the desktop (or anything else) so it is not in front.
set -euo pipefail

DIR="$HOME/PerchTest/perch-demo"
SOCK="/tmp/perch-take.sock"
SESSION="take"
MODEL="${PERCH_TAKE_MODEL:-haiku}"
PROMPT='Use the Bash tool to run exactly this command, nothing else: touch perch-was-here.txt. Then reply with one word: done.'
tm() { tmux -S "$SOCK" "$@"; }

case "${1:-}" in
  setup)
    mkdir -p "$DIR"
    [ -f "$DIR/README.md" ] || printf '# perch-demo\n\nA folder for filming Perch.\n' > "$DIR/README.md"
    if ! tm has-session -t "$SESSION" 2>/dev/null; then
      env -i HOME="$HOME" USER="$USER" SHELL=/bin/zsh LANG=en_US.UTF-8 TERM=xterm-256color \
        PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$HOME/.local/bin:$HOME/.claude/local" \
        tmux -S "$SOCK" new-session -d -s "$SESSION" -x 110 -y 28 -c "$DIR" "claude --model $MODEL"
      sleep 4
      # a new folder asks to be trusted first
      if tm capture-pane -p -t "$SESSION" | grep -qi "trust"; then tm send-keys -t "$SESSION" Enter; sleep 2; fi
    fi
    CMD="$DIR/.attach.command"
    printf '#!/bin/bash\nprintf "\\033]0;perch-demo\\007"\nexec tmux -S %s attach -t %s\n' "$SOCK" "$SESSION" > "$CMD"; chmod +x "$CMD"
    env -i HOME="$HOME" USER="$USER" SHELL=/bin/zsh TMPDIR="$(getconf DARWIN_USER_TEMP_DIR)" LANG=en_US.UTF-8 PATH=/usr/bin:/bin open -a Terminal "$CMD"
    sleep 1.5
    # under the notch, so the crop holds the notch and the top of the session
    osascript -e 'tell application "Terminal" to set bounds of front window to {476, 120, 1036, 520}' >/dev/null 2>&1 || true
    echo "notch-take: Claude Code is up in $DIR (tmux -S $SOCK)"
    ;;
  ask)
    tm send-keys -t "$SESSION" -l "$PROMPT"; sleep .2; tm send-keys -t "$SESSION" Enter
    ;;
  reset)
    tm send-keys -t "$SESSION" Escape; sleep .3; tm send-keys -t "$SESSION" -l "/clear"; tm send-keys -t "$SESSION" Enter
    rm -f "$DIR/perch-was-here.txt"
    ;;
  stop)
    tm kill-server 2>/dev/null || true
    osascript -e 'tell application "Terminal" to close (every window whose name contains "perch-demo")' >/dev/null 2>&1 || true
    ;;
  *) sed -n '2,13p' "$0"; exit 1 ;;
esac
