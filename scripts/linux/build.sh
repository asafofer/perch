#!/bin/sh
# Builds Perch for Linux with the Swift runtime inside it, so the machine that runs it needs no Swift.
# ./scripts/linux/build.sh [debug|release]   ->  .build/<config>/PerchLinux
set -e
cd "$(dirname "$0")/../.."
config=${1:-debug}
# Static Foundation needs its support libraries named; SwiftPM leaves them out.
swift build -c "$config" --product PerchLinux --static-swift-stdlib \
  -Xlinker -lCoreFoundation -Xlinker -l_FoundationICU -Xlinker -l_FoundationCShims \
  -Xlinker -l_FoundationCollections -Xlinker -lswiftSynchronization
# The Linux manifest has no dependencies, so SwiftPM deletes the Mac's Package.resolved (Sparkle's pin). Keep it.
git checkout -- Package.resolved 2>/dev/null || true
