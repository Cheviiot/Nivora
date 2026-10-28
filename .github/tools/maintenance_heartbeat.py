#!/usr/bin/env python3
"""Decide whether an empty maintenance heartbeat commit is due."""

from __future__ import annotations

import argparse
import sys
import time

HEARTBEAT_SECONDS = 30 * 24 * 60 * 60


def heartbeat_due(last_commit_time: int, now: int | None = None) -> bool:
    """Return whether the last commit is at least 30 days old (UTC epoch)."""
    if isinstance(last_commit_time, bool) or not isinstance(last_commit_time, int):
        raise ValueError("last commit time must be a nonnegative integer")
    if last_commit_time < 0:
        raise ValueError("last commit time must be a nonnegative integer")
    if now is None:
        now = int(time.time())
    if isinstance(now, bool) or not isinstance(now, int) or now < 0:
        raise ValueError("current time must be a nonnegative integer")
    return now >= last_commit_time and now - last_commit_time >= HEARTBEAT_SECONDS


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--last-commit-time", required=True, type=int)
    args = parser.parse_args()
    try:
        print("true" if heartbeat_due(args.last_commit_time) else "false")
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
