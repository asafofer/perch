#!/bin/bash
# Cut a release that installed copies update to by themselves (Sparkle).
#   ./scripts/release.sh              build, sign and write the appcast under build/appcast, nothing is published
#   ./scripts/release.sh --publish    also push the zip (a GitHub release) and appcast.xml to the public releases repo
# The version is CFBundleShortVersionString in Resources/Info.plist; the build number is the commit count, so every release is newer than the last.
# The private signing key lives in this Mac's keychain (made by Sparkle's generate_keys). Back it up: ./.build/artifacts/sparkle/Sparkle/bin/generate_keys -x perch-sparkle-key
set -euo pipefail
cd "$(dirname "$0")/.."
REPO=asafofer/perch-releases
SOURCE_REPO=asafofer/perch
BIN=.build/artifacts/sparkle/Sparkle/bin
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
# A release goes to everyone who has Perch: the tests must pass first.
swift test
./scripts/package.sh
# The disk image is for the first install (a window to drag Perch to Applications); updates come from the zip, so it stays out of build/appcast.
./scripts/make-dmg.sh
[ -x "$BIN/generate_appcast" ] || { echo "Sparkle tools missing: run swift build once"; exit 1; }
rm -rf build/appcast && mkdir -p build/appcast
cp build/Perch.zip "build/appcast/Perch-$VERSION.zip"
# What the notch says about this release: release-notes/<version>.md, a headline line then "- " lines (at most four are shown).
if [ -f "release-notes/$VERSION.md" ]; then cp "release-notes/$VERSION.md" "build/appcast/Perch-$VERSION.md"; else echo "No release-notes/$VERSION.md: the update will say nothing about what is new."; fi
# Earlier releases stay in the appcast: start from the published one when there is one.
curl -fsSL "https://raw.githubusercontent.com/$REPO/main/appcast.xml" -o build/appcast/appcast.xml 2>/dev/null || rm -f build/appcast/appcast.xml
"$BIN/generate_appcast" --embed-release-notes --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" build/appcast
echo "Ready: build/appcast/Perch-$VERSION.zip, build/Perch.dmg and appcast.xml (version $VERSION, build $(git rev-list --count HEAD))"
[ "${1:-}" = "--publish" ] || { echo "Not published. Run again with --publish."; exit 0; }
gh release create "v$VERSION" "build/appcast/Perch-$VERSION.zip" build/Perch.dmg --repo "$REPO" --title "Perch $VERSION" --notes "Perch $VERSION"
# The source repo's Releases page says the same, with what is new, so it never falls behind (the zip there is for people with access; updates come from $REPO).
NOTES="Perch $VERSION"; [ -f "release-notes/$VERSION.md" ] && NOTES="$(cat "release-notes/$VERSION.md")"
gh release create "v$VERSION" "build/appcast/Perch-$VERSION.zip" build/Perch.dmg --repo "$SOURCE_REPO" --target "$(git rev-parse HEAD)" --title "Perch $VERSION" --notes "$NOTES" || echo "The release in $SOURCE_REPO was not made (the one in $REPO is): make it by hand."
# appcast.xml goes to the repo's main branch through the contents API: the feed is read from there.
SHA=$(gh api "repos/$REPO/contents/appcast.xml" -q .sha 2>/dev/null || true)
gh api -X PUT "repos/$REPO/contents/appcast.xml" -f message="Perch $VERSION" -f content="$(base64 < build/appcast/appcast.xml)" ${SHA:+-f sha="$SHA"} >/dev/null
# GitHub serves the feed from a cache that lasts up to five minutes. Perch asks with a different address each time (Updater.feedParameters), so it sees a release at once; this looks the same way.
echo "Published. Checking the public feed shows $VERSION..."
for _ in $(seq 40); do
  curl -fsS "https://raw.githubusercontent.com/$REPO/main/appcast.xml?t=$(date +%s)" 2>/dev/null | grep -q "<sparkle:shortVersionString>$VERSION<" && { echo "Live: Perch $VERSION is in the feed. Copies of Perch check once a day, or at once with Check for updates."; exit 0; }
  sleep 10
done
echo "Published, but the feed still shows the old version after a while: check https://raw.githubusercontent.com/$REPO/main/appcast.xml"
