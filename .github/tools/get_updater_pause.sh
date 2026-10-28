#!/bin/bash
set -euo pipefail

repository="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
title='[autoupdate] обновления приостановлены'
marker='<!-- nivora-updater-paused -->'

die() {
    echo "get_updater_pause: $*" >&2
    exit 1
}

issues="$(
    gh api --paginate --slurp \
        "repos/${repository}/issues?state=open&per_page=100"
)" || die 'cannot read updater pause issue'

# Issue bodies can exceed the per-environment-variable size limit. Pass the
# response on a file descriptor while stdin carries the parser itself.
python3 - "$title" "$marker" 3<<<"$issues" <<'PY'
import json
import os
import re
import sys

title, marker = sys.argv[1:]
try:
    with os.fdopen(3) as response:
        pages = json.load(response)
except json.JSONDecodeError as error:
    print(f"get_updater_pause: invalid issue response: {error}", file=sys.stderr)
    raise SystemExit(1)
if not isinstance(pages, list) or any(not isinstance(page, list) for page in pages):
    print("get_updater_pause: invalid issue response shape", file=sys.stderr)
    raise SystemExit(1)

issues = [
    issue
    for page in pages
    for issue in page
    if isinstance(issue, dict)
    and "pull_request" not in issue
    and issue.get("user", {}).get("login") == "github-actions[bot]"
    and issue.get("title") == title
    and (issue.get("body") or "").split("\n", 1)[0] == marker
]

if not issues:
    print(json.dumps({"paused": False, "sha": ""}))
    raise SystemExit(0)
if len(issues) != 1:
    print("get_updater_pause: multiple open updater pause issues found", file=sys.stderr)
    raise SystemExit(1)

body = issues[0].get("body") or ""
sha_lines = [
    line
    for line in body.splitlines()
    if line.startswith("<!-- nivora-updater-paused-sha:")
]
if sha_lines:
    if len(sha_lines) != 1:
        print("get_updater_pause: malformed updater pause SHA metadata", file=sys.stderr)
        raise SystemExit(1)
    match = re.fullmatch(r"<!-- nivora-updater-paused-sha: ([0-9a-f]{40}) -->", sha_lines[0])
    if not match:
        print("get_updater_pause: malformed updater pause SHA metadata", file=sys.stderr)
        raise SystemExit(1)
    sha = match.group(1)
else:
    # Migrate issues written by the previous template without the hidden SHA
    # metadata. Keep this exact sentence in future issue bodies for readability.
    matches = re.findall(
        r"^Автоматические обновления приостановлены после сбоя проверки "
        r"точного commit \*\*([0-9a-f]{40})\*\*\.$",
        body,
        re.MULTILINE,
    )
    if len(matches) != 1:
        print("get_updater_pause: missing or malformed updater pause SHA", file=sys.stderr)
        raise SystemExit(1)
    sha = matches[0]

print(json.dumps({"paused": True, "sha": sha}))
PY
