#!/bin/bash
# Build a release Perch.app and zip it for sharing: build/Perch.zip
# Signed with the local "Perch Dev" certificate when present, otherwise ad hoc.
# It is not notarized: whoever unzips it must right-click the app and choose Open the first time.
set -euo pipefail
cd "$(dirname "$0")/.."
( cd ui && { [ -d node_modules ] || npm install --silent; } )
CONFIG=release ./scripts/run.sh --package-only
rm -f build/Perch.zip
ditto -c -k --norsrc --keepParent build/Perch.app build/Perch.zip
echo "Packaged: $(pwd)/build/Perch.zip ($(du -h build/Perch.zip | cut -f1))"
