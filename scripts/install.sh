#!/bin/bash
# Build Perch in release mode and install it to /Applications (or ~/Applications), then open it.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/package.sh
DEST=/Applications; [ -w "$DEST" ] || { DEST="$HOME/Applications"; mkdir -p "$DEST"; }
pkill -x Perch 2>/dev/null || true
rm -rf "$DEST/Perch.app"
cp -R build/Perch.app "$DEST/Perch.app"
open "$DEST/Perch.app"
echo "Installed to $DEST/Perch.app"
