#!/bin/bash
# Notarize a Developer ID signed Perch.app or Perch.dmg with Apple and staple the ticket to it, so Gatekeeper opens it without asking, even offline.
#   ./scripts/notarize.sh build/Perch.app
# Once per Mac, store the credentials in the keychain (it asks for an app-specific password, made at account.apple.com):
#   xcrun notarytool store-credentials perch-notary --apple-id <your Apple Account> --team-id <your team id>
set -euo pipefail
PROFILE=${PERCH_NOTARY_PROFILE:-perch-notary}
TARGET=${1:?usage: notarize.sh <Perch.app or Perch.dmg>}
SUBMIT=$TARGET
# notarytool takes a zip, a dmg or a pkg, not a bare .app
if [[ "$TARGET" == *.app ]]; then
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  SUBMIT="$TMP/$(basename "$TARGET" .app).zip"
  ditto -c -k --norsrc --keepParent "$TARGET" "$SUBMIT"
fi
echo "Notarizing $TARGET (usually a few minutes)..."
OUT=$(xcrun notarytool submit "$SUBMIT" --keychain-profile "$PROFILE" --wait --output-format json)
ID=$(sed -n 's/.*"id" *: *"\([^"]*\)".*/\1/p' <<<"$OUT")
if ! grep -q '"status" *: *"Accepted"' <<<"$OUT"; then
  echo "Apple did not accept $TARGET:"; echo "$OUT"
  [ -n "$ID" ] && xcrun notarytool log "$ID" --keychain-profile "$PROFILE"
  exit 1
fi
xcrun stapler staple "$TARGET"
# what Gatekeeper will say on someone else's Mac
if [[ "$TARGET" == *.app ]]; then spctl -a -t exec -vv "$TARGET"; else spctl -a -t open --context context:primary-signature -vv "$TARGET"; fi
echo "Notarized and stapled: $TARGET"
