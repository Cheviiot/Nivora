#!/usr/bin/env python3
"""Bound retries for an identical failed package update candidate."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any


COOLDOWN = timedelta(hours=6)
PACKAGE_ID = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
VERSION = re.compile(r"^[A-Za-z0-9.+~_-]{1,128}$")
FINGERPRINT_NAME = re.compile(r"^source_fingerprint(?:_(?:amd64|arm64))?$")
FINGERPRINT = re.compile(r"^[0-9a-f]{64}$")
CANDIDATE_MARKER = re.compile(r"^<!-- nivora-update-candidate: ([0-9a-f]{64}) -->$")
RETRY_MARKER = re.compile(r"^<!-- nivora-update-retry-after: (.+) -->$")
RECIPE_VERSION = re.compile(r"^version=(?:'([^'\r\n]*)'|\"([^\"\r\n]*)\"|([^#\s]+))$")
ISSUE_MARKER = "<!-- nivora-autonomous-update:{package} -->"


class InvalidInput(ValueError):
    """Raised when trusted plan input is malformed."""


def parse_time(value: str | None) -> datetime:
    if value is None:
        return datetime.now(timezone.utc)
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise InvalidInput(f"invalid ISO timestamp: {value}") from error
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise InvalidInput("timestamp must include a timezone")
    return parsed.astimezone(timezone.utc)


def read_plan(path: Path) -> dict[str, dict[str, Any]]:
    def unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise InvalidInput(f"duplicate JSON key in update plan: {key}")
            result[key] = value
        return result

    try:
        value = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique_object)
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise InvalidInput(f"cannot read update plan: {path}") from error
    if not isinstance(value, dict):
        raise InvalidInput("update plan must be an object")

    result: dict[str, dict[str, Any]] = {}
    for package, entry in value.items():
        if not isinstance(package, str) or not PACKAGE_ID.fullmatch(package):
            raise InvalidInput(f"unsafe package id: {package!r}")
        if not isinstance(entry, dict) or set(entry) != {"current", "latest", "fingerprints"}:
            raise InvalidInput(f"invalid update entry: {package}")
        current = entry["current"]
        latest = entry["latest"]
        fingerprints = entry["fingerprints"]
        if (
            not isinstance(current, str)
            or not VERSION.fullmatch(current)
            or not isinstance(latest, str)
            or not VERSION.fullmatch(latest)
            or not isinstance(fingerprints, dict)
        ):
            raise InvalidInput(f"invalid update values: {package}")
        for name, fingerprint in fingerprints.items():
            if (
                not isinstance(name, str)
                or not FINGERPRINT_NAME.fullmatch(name)
                or not isinstance(fingerprint, str)
                or not FINGERPRINT.fullmatch(fingerprint)
            ):
                raise InvalidInput(f"invalid source fingerprint: {package}")
        result[package] = {
            "current": current,
            "latest": latest,
            "fingerprints": dict(sorted(fingerprints.items())),
        }
    return result


def recipe_path(repo_root: Path, package: str) -> Path:
    if not PACKAGE_ID.fullmatch(package):
        raise InvalidInput(f"unsafe package id: {package!r}")
    root = repo_root.resolve(strict=True)
    unresolved_package_dir = root / package
    if unresolved_package_dir.is_symlink():
        raise InvalidInput(f"package directory must not be a symlink: {package}")
    package_dir = unresolved_package_dir.resolve(strict=True)
    if package_dir.parent != root:
        raise InvalidInput(f"package directory escapes repository: {package}")
    path = package_dir / "Staplerfile"
    if path.is_symlink() or not path.is_file():
        raise InvalidInput(f"missing regular Staplerfile: {package}")
    return path


def candidate_key(repo_root: Path, package: str, entry: dict[str, Any]) -> str:
    path = recipe_path(repo_root, package)
    recipe_digest = hashlib.sha256(path.read_bytes()).hexdigest()
    payload = {
        "package": package,
        "current": entry["current"],
        "latest": entry["latest"],
        "fingerprints": entry["fingerprints"],
        "recipe_sha256": recipe_digest,
    }
    canonical = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def flatten_issue_pages(value: Any) -> list[dict[str, Any]]:
    if not isinstance(value, list):
        return []
    pages: list[Any] = []
    for page in value:
        if isinstance(page, list):
            pages.extend(page)
        elif isinstance(page, dict):
            pages.append(page)
        else:
            return []
    return [item for item in pages if isinstance(item, dict)]


def read_issues(path: Path) -> list[dict[str, Any]]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        # A malformed issue snapshot must never keep a candidate blocked.
        return []
    return flatten_issue_pages(value)


def is_candidate_issue(issue: dict[str, Any], package: str) -> bool:
    user = issue.get("user")
    if (
        issue.get("state") != "open"
        or not isinstance(user, dict)
        or user.get("login") != "github-actions[bot]"
        or "pull_request" in issue
        or issue.get("title")
        not in {
            f"[autoupdate] {package}: требуется диагностика",
            f"[autoupdate] {package}: обновление отложено",
        }
    ):
        return False
    body = issue.get("body")
    if not isinstance(body, str) or not body.startswith(ISSUE_MARKER.format(package=package) + "\n"):
        return False
    return True


def issue_metadata(issue: dict[str, Any], package: str) -> tuple[str, datetime] | None:
    if not is_candidate_issue(issue, package):
        return None
    body = issue["body"]
    candidate_lines = [line for line in body.splitlines() if line.startswith("<!-- nivora-update-candidate:")]
    retry_lines = [line for line in body.splitlines() if line.startswith("<!-- nivora-update-retry-after:")]
    if len(candidate_lines) != 1 or len(retry_lines) != 1:
        return None
    candidate_match = CANDIDATE_MARKER.fullmatch(candidate_lines[0])
    retry_match = RETRY_MARKER.fullmatch(retry_lines[0])
    if not candidate_match or not retry_match:
        return None
    try:
        retry_after = parse_time(retry_match.group(1))
    except InvalidInput:
        return None
    return candidate_match.group(1), retry_after


def filter_plan(
    plan: dict[str, dict[str, Any]], issues: list[dict[str, Any]], repo_root: Path, now: datetime
) -> dict[str, Any]:
    issue_groups: dict[str, list[dict[str, Any]]] = {package: [] for package in plan}
    for issue in issues:
        for package in plan:
            if is_candidate_issue(issue, package):
                issue_groups[package].append(issue)
                break

    eligible: list[str] = []
    deferred: list[str] = []
    candidate_keys: dict[str, str] = {}
    expected_updates: dict[str, dict[str, Any]] = {}
    for package, entry in plan.items():
        key = candidate_key(repo_root, package, entry)
        candidate_keys[package] = key
        matching = issue_groups[package]
        metadata = issue_metadata(matching[0], package) if len(matching) == 1 else None
        if (
            metadata
            and metadata[0] == key
            and now < metadata[1] <= now + COOLDOWN
        ):
            deferred.append(package)
        else:
            eligible.append(package)
            expected_updates[package] = entry
    return {
        "packages": eligible,
        "deferred": deferred,
        "expected_updates": expected_updates,
        "candidate_keys": candidate_keys,
    }


def recipe_version(path: Path) -> str | None:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError):
        return None
    matches = [match for line in lines if (match := RECIPE_VERSION.fullmatch(line))]
    if len(matches) != 1:
        return None
    return next(group for group in matches[0].groups() if group is not None)


def stamp_candidate(
    package: str, plan_path: Path, repo_root: Path, now: datetime
) -> str:
    try:
        plan = read_plan(plan_path)
        entry = plan.get(package)
        if entry is None:
            return ""
        path = recipe_path(repo_root, package)
        if recipe_version(path) != entry["current"]:
            return ""
        key = candidate_key(repo_root, package, entry)
    except (InvalidInput, OSError):
        # Detection failures and stale plans should be retried on the next run.
        return ""
    retry_after = (now + COOLDOWN).isoformat(timespec="seconds").replace("+00:00", "Z")
    return (
        f"<!-- nivora-update-candidate: {key} -->\n"
        f"<!-- nivora-update-retry-after: {retry_after} -->"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    filter_parser = subparsers.add_parser("filter")
    filter_parser.add_argument("--plan", type=Path, required=True)
    filter_parser.add_argument("--issues", type=Path, required=True)
    filter_parser.add_argument("--repo-root", type=Path, required=True)
    filter_parser.add_argument("--now")
    stamp_parser = subparsers.add_parser("stamp")
    stamp_parser.add_argument("--package", required=True)
    stamp_parser.add_argument("--plan", type=Path, required=True)
    stamp_parser.add_argument("--repo-root", type=Path, required=True)
    stamp_parser.add_argument("--now")
    args = parser.parse_args()

    if args.command == "stamp":
        try:
            now = parse_time(args.now)
        except InvalidInput as error:
            print(f"candidate_backoff: {error}", file=sys.stderr)
            return 2
        value = stamp_candidate(args.package, args.plan, args.repo_root, now)
        if value:
            print(value)
        return 0

    try:
        plan = read_plan(args.plan)
        now = parse_time(args.now)
        result = filter_plan(plan, read_issues(args.issues), args.repo_root, now)
    except (InvalidInput, OSError) as error:
        print(f"candidate_backoff: {error}", file=sys.stderr)
        return 2
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
