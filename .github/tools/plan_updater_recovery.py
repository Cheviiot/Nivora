#!/usr/bin/env python3
"""Choose whether a paused updater should dispatch a full recovery run."""

from __future__ import annotations

import json
import re
import sys
from datetime import datetime, timedelta, timezone
from typing import Any


SHA_PATTERN = re.compile(r"^[0-9a-f]{40}$")
RECOVERY_TITLE = re.compile(
    r"^post-push (?P<sha>[0-9a-f]{40}) · updater [^·]* · resume (?P<resume>true|false)$"
)
COOLDOWN = timedelta(hours=6)
ACTIVE_STATUSES = {"queued", "in_progress", "waiting", "requested", "pending"}


def parse_timestamp(value: str) -> datetime:
    """Parse a GitHub ISO timestamp and normalize it to UTC."""
    if not isinstance(value, str):
        raise ValueError("workflow run has no valid timestamp")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise ValueError("workflow run has malformed timestamp") from error
    if parsed.tzinfo is None:
        raise ValueError("workflow run timestamp has no timezone")
    return parsed.astimezone(timezone.utc)


def run_updated_at(run: dict[str, Any]) -> datetime:
    """Use completion/update time for cooldowns, with legacy API fallback."""
    value = run.get("updated_at")
    if value is None:
        value = run.get("created_at")
    return parse_timestamp(value)


def flattened_runs(value: Any) -> list[dict[str, Any]]:
    """Accept either the run array or the array of pages produced by gh --slurp."""
    if not isinstance(value, list):
        raise ValueError("workflow runs must be an array")
    runs: list[dict[str, Any]] = []
    for item in value:
        if isinstance(item, list):
            page = item
        else:
            page = [item]
        if any(not isinstance(run, dict) for run in page):
            raise ValueError("workflow run entry must be an object")
        runs.extend(page)
    return runs


def plan_recovery(request: dict[str, Any]) -> dict[str, str]:
    """Return dispatch or a safe no-op from the issue and recent workflow runs."""
    pause = request.get("pause_state")
    if not isinstance(pause, dict) or not isinstance(pause.get("paused"), bool):
        raise ValueError("pause_state must contain a boolean paused field")
    if not pause["paused"]:
        return {"action": "none", "reason": "not-paused"}

    paused_sha = pause.get("sha")
    current_sha = request.get("current_sha")
    if not isinstance(paused_sha, str) or not SHA_PATTERN.fullmatch(paused_sha):
        raise ValueError("paused issue has a malformed SHA")
    if not isinstance(current_sha, str) or not SHA_PATTERN.fullmatch(current_sha):
        raise ValueError("current main has a malformed SHA")

    is_ancestor = request.get("paused_sha_is_ancestor")
    if not isinstance(is_ancestor, bool):
        raise ValueError("paused_sha_is_ancestor must be a boolean")
    if not is_ancestor:
        return {"action": "none", "reason": "pause-sha-not-ancestor"}

    now = parse_timestamp(request.get("now"))
    matching: list[dict[str, Any]] = []
    for run in flattened_runs(request.get("workflow_runs", [])):
        title = run.get("display_title", "")
        match = RECOVERY_TITLE.fullmatch(title) if isinstance(title, str) else None
        if not match or match.group("resume") != "true":
            continue
        if match.group("sha") == current_sha:
            matching.append(run)

    for run in matching:
        status = run.get("status")
        if status in ACTIVE_STATUSES:
            return {"action": "none", "reason": "recovery-active"}
        if status != "completed":
            raise ValueError("matching recovery has an unknown workflow status")

    failed_runs = [run for run in matching if run.get("conclusion") != "success"]
    if failed_runs:
        latest_failure = max(failed_runs, key=run_updated_at)
        failed_at = run_updated_at(latest_failure)
        if now - failed_at < COOLDOWN:
            return {"action": "none", "reason": "retry-cooldown"}

    reason = "retry-after-cooldown" if failed_runs else "new-recovery"
    return {"action": "dispatch", "reason": reason, "sha": current_sha}


def main() -> int:
    try:
        request = json.load(sys.stdin)
        if not isinstance(request, dict):
            raise ValueError("request must be a JSON object")
        result = plan_recovery(request)
    except (json.JSONDecodeError, ValueError) as error:
        print(f"plan_updater_recovery: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
