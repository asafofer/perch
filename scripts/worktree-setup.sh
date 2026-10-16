#!/bin/bash
# Gets a checkout ready for work: Claude Code runs it when a session starts (SessionStart hook).
# Quiet and idempotent; each step only runs when its piece is missing.
#   - ui/node_modules (npm ci), so `npm run build` works
#   - ui/icons.local.json from the main checkout, so the design page shows the real app icons
#   - .claude/launch.json with a port of this checkout's own, so the design server never shows
#     another worktree's files
set -u
cd "$(dirname "$0")/.." || exit 0
ROOT=$(pwd)
MAIN=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)")

if [ ! -d ui/node_modules ] && command -v npm >/dev/null; then
  (cd ui && npm ci --prefer-offline --no-audit --no-fund --loglevel=error >/dev/null 2>&1) \
    && echo "worktree-setup: installed ui/node_modules"
fi

if [ ! -f ui/icons.local.json ] && [ -n "$MAIN" ] && [ "$MAIN" != "$ROOT" ] && [ -f "$MAIN/ui/icons.local.json" ]; then
  cp "$MAIN/ui/icons.local.json" ui/ && echo "worktree-setup: copied ui/icons.local.json"
fi

if [ ! -f .claude/launch.json ]; then
  # 8700-8899, fixed per checkout path.
  PORT=$((8700 + $(printf '%s' "$ROOT" | cksum | cut -d' ' -f1) % 200))
  cat > .claude/launch.json <<EOF
{
  "version": "0.0.1",
  "configurations": [
    {
      "name": "design",
      "runtimeExecutable": "python3",
      "runtimeArgs": ["-m", "http.server", "$PORT", "--bind", "127.0.0.1", "--directory", "ui"],
      "port": $PORT
    }
  ]
}
EOF
  echo "worktree-setup: design server for this checkout is preview_start \"design\" (port $PORT)"
fi
exit 0
