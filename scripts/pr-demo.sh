#!/bin/bash
# A PR's demo, filmed from the design page: the scenarios it adds or changes, played one after another with a caption
# naming each. Writes build/pr-demo/: demo.mp4, demo.gif, a still of each scenario (NN-name.png) and demo.md, the
# PR body's Demo section. --publish puts the files on the pr-media branch and writes that section into the open PR.
#
#   ./scripts/pr-demo.sh                        scenarios whose lines in ui/design.html changed since main
#   ./scripts/pr-demo.sh "Needs your OK" "Settings/Resting"   these, in this order (Group/Name where two share a name)
#   ./scripts/pr-demo.sh --list                 every scenario, as Group/Name
#   --hold <s>   seconds each (default 4)    --base <ref>   what "changed" is measured against (default origin/main)
#   --publish    push the media and update this branch's PR
#
# Needs ffmpeg. Headless: nothing shows on screen and the keyboard is never taken.
set -euo pipefail
cd "$(dirname "$0")/.."
HOLD=4 BASE=origin/main PUBLISH=0 LIST=0 NAMES=()
while [ $# -gt 0 ]; do case $1 in
  --hold) HOLD=$2; shift 2 ;; --base) BASE=$2; shift 2 ;; --publish) PUBLISH=1; shift ;; --list) LIST=1; shift ;;
  -h|--help) sed -n 2,13p "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) NAMES+=("$1"); shift ;; esac; done

# Every scenario as "Group/Name<TAB>what it shows", from GROUPS in the design page; with a diff on stdin, only those it touches.
scenarios() { python3 -I - ui/design.html "$@" <<'PY'
import json, re, sys
S = r"'((?:[^'\\]|\\.)*)'"
js = lambda s: json.loads('"' + s.replace("\\'", "'").replace('"', '\\"') + '"')
touched = None
if len(sys.argv) > 2:
    touched = {js(m.group(1)) for l in open(sys.argv[2]) if l.startswith('+') for m in [re.match(r"\+\s*\[" + S + r", '", l)] if m}
group = None
for line in open(sys.argv[1]):
    g = re.match(r"\s{4}\[" + S + r", \[\s*$", line)
    if g: group = js(g.group(1)); continue
    s = re.match(r"\s{6}\[" + S + r", " + S, line)
    if group and s:
        name = js(s.group(1))
        if touched is None or name in touched:
            print(f"{group}/{name}\t{re.split(r'(?<=[.!?])\s', js(s.group(2)))[0]}")
PY
}

if [ $LIST = 1 ]; then scenarios | cut -f1; exit 0; fi
OUT=build/pr-demo; rm -rf "$OUT"; mkdir -p "$OUT"
if [ ${#NAMES[@]} -eq 0 ]; then
  git diff -U0 "$(git merge-base "$BASE" HEAD)" -- ui/design.html > "$OUT/.diff"
  while IFS= read -r l; do NAMES+=("${l%%$'\t'*}"); done < <(scenarios "$OUT/.diff")
  [ ${#NAMES[@]} -gt 0 ] || { echo "No scenario in ui/design.html changed since $BASE. Name the ones to film (--list shows them)."; exit 1; }
fi
# What each one shows, for the stills table (and a check that each name exists)
: > "$OUT/.what"
for n in "${NAMES[@]}"; do
  hit=$(scenarios | awk -F'\t' -v n="$n" '$1 == n || substr($1, index($1, "/") + 1) == n { print; exit }')
  [ -n "$hit" ] || { echo "No scenario named \"$n\" (--list shows them)."; exit 1; }
  echo "$hit" >> "$OUT/.what"
done
echo "Filming ${#NAMES[@]} scenario(s), ${HOLD}s each:"; cut -f1 "$OUT/.what" | sed 's/^/  /'

PLAY=$(cut -f1 "$OUT/.what" | python3 -I -c 'import sys, urllib.parse; print(urllib.parse.quote("|".join(sys.stdin.read().split("\n")[:-1]), safe=""))')
( cd ui && npm run build --silent )
PORT=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')   # a fixed one may be another worktree's
python3 -m http.server $PORT --directory ui >/dev/null 2>&1 & SERVER=$!
trap 'kill $SERVER 2>/dev/null || true' EXIT
sleep 0.6
FRAMES=$(mktemp -d)
SECONDS_TOTAL=$(python3 -c "print(0.6 + ${#NAMES[@]} * $HOLD)")
swift scripts/record-design.swift "http://localhost:$PORT/design.html?record&hold=$HOLD&play=$PLAY" "$FRAMES" "$SECONDS_TOTAL" 840 340
COUNT=$(ls "$FRAMES" | wc -l | tr -d ' ')
echo "$COUNT frames"

ffmpeg -loglevel error -y -framerate 20 -pattern_type glob -i "$FRAMES/f*.png" \
  -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v libx264 -pix_fmt yuv420p -crf 20 -movflags +faststart "$OUT/demo.mp4"
ffmpeg -loglevel error -y -framerate 20 -pattern_type glob -i "$FRAMES/f*.png" \
  -vf "fps=20,scale=720:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle" "$OUT/demo.gif"
# A still of each, a little before it gives way to the next (the page starts 0.3 s in)
i=0
while IFS=$'\t' read -r name _; do
  f=$(python3 -c "print(min($COUNT, max(1, round((0.3 + ($i + 1) * $HOLD - 0.5) * 20))))")
  slug=$(echo "$name" | tr 'A-Z' 'a-z' | sed 's/[^a-z0-9]\{1,\}/-/g; s/^-//; s/-$//')
  cp "$FRAMES/$(printf 'f%05d.png' "$f")" "$OUT/$(printf '%02d' $((i + 1)))-$slug.png"
  i=$((i + 1))
done < "$OUT/.what"
rm -rf "$FRAMES"

# demo.md: the PR body's Demo section. Media links are filled in by --publish; locally they point at the files.
write_md() {  # $1: url prefix for the files
  {
    echo "<!-- demo -->"
    echo "![Demo]($1demo.gif)"
    echo
    echo "[MP4, full resolution]($1demo.mp4) · filmed from \`ui/design.html\` by \`./scripts/pr-demo.sh\`"
    echo
    echo "| Scenario | What it shows | Still |"
    echo "|---|---|---|"
    for png in "$OUT"/[0-9][0-9]-*.png; do
      k=$((10#$(basename "$png" | cut -c1-2)))
      IFS=$'\t' read -r name what < <(sed -n "${k}p" "$OUT/.what")
      echo "| $name | ${what//|/\\|} | <img src=\"$1$(basename "$png")\" width=\"360\"> |"
    done
    echo "<!-- /demo -->"
  } > "$OUT/demo.md"
}
write_md ""
echo "Wrote $OUT: demo.mp4 ($(du -h "$OUT/demo.mp4" | cut -f1)), demo.gif ($(du -h "$OUT/demo.gif" | cut -f1)), $i still(s), demo.md"
[ $PUBLISH = 1 ] || exit 0

# --publish: the files go on the pr-media branch (an orphan branch only for PR media, so main never carries them) under
# pr-<number>/, committed with a scratch index so this checkout is left alone; links name the commit, so they stay put.
PR=$(gh pr view --json number -q .number) || { echo "No PR for this branch yet: open it first (gh pr create), then --publish."; exit 1; }
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
PARENT=
if git ls-remote -q --exit-code origin refs/heads/pr-media >/dev/null; then git fetch -q origin pr-media; PARENT=$(git rev-parse FETCH_HEAD); fi
export GIT_INDEX_FILE=$(mktemp -u)
if [ -n "$PARENT" ]; then git read-tree "$PARENT"; git rm -rq --cached --ignore-unmatch "pr-$PR"; else git read-tree --empty; fi
for f in "$OUT"/demo.mp4 "$OUT"/demo.gif "$OUT"/[0-9][0-9]-*.png; do
  git update-index --add --cacheinfo "100644,$(git hash-object -w "$f"),pr-$PR/$(basename "$f")"
done
COMMIT=$(git commit-tree "$(git write-tree)" ${PARENT:+-p "$PARENT"} -m "Demo for #$PR")
rm -f "$GIT_INDEX_FILE"; unset GIT_INDEX_FILE
git push -q --no-verify origin "$COMMIT:refs/heads/pr-media"   # media only: the pre-push tests guard code, not this
write_md "https://github.com/$REPO/blob/$COMMIT/pr-$PR/"
sed -i '' 's/\(blob\/[0-9a-f]*\/pr-[0-9]*\/[^)" ]*\)/\1?raw=true/g' "$OUT/demo.md"
# The Demo section of the body, between its markers, or added at the end when the body has none
gh pr view "$PR" --json body -q .body > "$OUT/.body"
python3 -I - "$OUT/.body" "$OUT/demo.md" <<'PY'
import re, sys
body, demo = open(sys.argv[1]).read(), open(sys.argv[2]).read().strip()
new = re.sub(r"<!-- demo -->.*?<!-- /demo -->", lambda _: demo, body, flags=re.S) if "<!-- demo -->" in body else body.rstrip() + "\n\n## Demo\n\n" + demo + "\n"
open(sys.argv[1], "w").write(new)
PY
gh pr edit "$PR" --body-file "$OUT/.body" >/dev/null
echo "Published to pr-media ($COMMIT) and updated #$PR: $(gh pr view "$PR" --json url -q .url)"
