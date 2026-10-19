#!/usr/bin/env python3
# PreToolUse hook (Bash): a `gh pr create` goes through only with a body that follows .github/pull_request_template.md,
# so every PR carries its demo. Anything else passes untouched. Exit 2 refuses and tells the agent why.
# CI runs the same rules on every PR's body, wherever it was opened: pr-body-check.py <file with the body>.
import json, os, re, shlex, sys

ci = len(sys.argv) > 1
if ci:
    body, args = open(sys.argv[1]).read(), []
else:
    cmd = json.load(sys.stdin).get("tool_input", {}).get("command", "")
    if not re.search(r"\bgh\s+pr\s+create\b", cmd):
        sys.exit(0)
    try:
        args = shlex.split(cmd)
    except ValueError:
        args = cmd.split()
    body = None
    # A PR into another repo (the website's, say) has its own rules: only Perch's template is enforced here.
    repo = None
    for i, a in enumerate(args):
        if a in ("--repo", "-R") and i + 1 < len(args):
            repo = args[i + 1]
        elif a.startswith("--repo=") or a.startswith("-R="):
            repo = a.split("=", 1)[1]
        elif a.startswith("-R") and len(a) > 2:
            repo = a[2:]
    if repo and "/".join(repo.rstrip("/").split("/")[-2:]).lower() != "asafofer/perch":
        sys.exit(0)
for i, a in enumerate(args):
    for flag in ("--body-file", "-F"):
        if a == flag and i + 1 < len(args):
            path = args[i + 1]
            try:
                body = open(os.path.expanduser(path)).read()
            except OSError:
                body = ""
        elif a.startswith(flag + "="):
            try:
                body = open(os.path.expanduser(a.split("=", 1)[1])).read()
            except OSError:
                body = ""
    if a in ("--body", "-b") and i + 1 < len(args):
        body = args[i + 1]
    elif a.startswith("--body="):
        body = a.split("=", 1)[1]

missing = []
if body is None:
    missing.append("a body (--body-file with the filled template)")
else:
    for h in ("## What changes", "## Demo", "## What's new, changed, removed", "## Try it", "## Where in the code",
              "## Risk and what was not checked", "## Checks"):
        if h not in body:
            missing.append(h)
    if "<!-- demo -->" not in body and "No visible change" not in body:
        missing.append("the Demo markers (<!-- demo --> <!-- /demo -->) or \"No visible change.\"")
if missing and ci:
    print("The PR description follows .github/pull_request_template.md (CONTRIBUTING.md says how). Missing: "
          + "; ".join(missing) + ". Edit the description and this check runs again.", file=sys.stderr)
    sys.exit(1)
if missing:
    print("This repo's PRs follow .github/pull_request_template.md (see \"Opening a PR\" in AGENTS.md, or the open-pr "
          "skill). Missing: " + "; ".join(missing) + ". Fill the template into a file, pass it with --body-file, then "
          "run ./scripts/pr-demo.sh --publish once the PR exists.", file=sys.stderr)
    sys.exit(2)
