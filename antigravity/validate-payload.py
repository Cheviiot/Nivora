#!/usr/bin/env python3
"""Validate the pinned tar payload without executing proprietary binaries."""

from __future__ import annotations

import json
import struct
import sys
from pathlib import Path, PurePosixPath


def validate(payload: Path, expected_version: str) -> None:
    machines = {"Antigravity-x64": 62, "Antigravity-arm64": 183}
    if payload.name not in machines:
        raise ValueError(f"unexpected archive root: {payload.name}")

    for filename in ("antigravity", "chrome-sandbox"):
        with (payload / filename).open("rb") as stream:
            elf = stream.read(20)
        if len(elf) != 20 or elf[:6] != b"\x7fELF\x02\x01":
            raise ValueError(f"{filename} is not a little-endian ELF64 binary")
        machine = struct.unpack_from("<H", elf, 18)[0]
        if machine != machines[payload.name]:
            raise ValueError(f"{filename} architecture does not match {payload.name}")

    for filename in ("LICENSE.electron.txt", "LICENSES.chromium.html"):
        if not (payload / filename).is_file() or not (payload / filename).stat().st_size:
            raise ValueError(f"missing upstream license: {filename}")

    asar_path = payload / "resources/app.asar"
    with asar_path.open("rb") as stream:
        prefix = stream.read(16)
        if len(prefix) != 16:
            raise ValueError("truncated ASAR header")
        size_size, header_size, pickle_size, json_size = struct.unpack("<4I", prefix)
        if (
            size_size != 4
            or not 0 < json_size <= 16 * 1024 * 1024
            or header_size != 8 + ((json_size + 3) & ~3)
            or pickle_size != header_size - 4
        ):
            raise ValueError("invalid ASAR header")
        header = json.loads(stream.read(json_size))
        data_start = 8 + header_size
        archive_size = asar_path.stat().st_size
        if data_start > archive_size:
            raise ValueError("truncated ASAR header")

        def entry_for(name: str) -> dict:
            path = PurePosixPath(name)
            if not name or path.is_absolute() or ".." in path.parts:
                raise ValueError(f"invalid ASAR entry path: {name!r}")
            entry = header
            for part in path.parts:
                entry = entry["files"][part]
            return entry

        def packed_range(entry: dict) -> tuple[int, int]:
            if entry.get("unpacked") or "link" in entry:
                raise ValueError("expected a packed ASAR file")
            offset, size = int(entry["offset"]), int(entry["size"])
            if offset < 0 or size <= 0 or data_start + offset + size > archive_size:
                raise ValueError("ASAR file lies outside the archive")
            return data_start + offset, size

        manifest_offset, manifest_size = packed_range(entry_for("package.json"))
        if manifest_size > 1024 * 1024:
            raise ValueError("unexpectedly large root package.json")
        stream.seek(manifest_offset)
        manifest = json.loads(stream.read(manifest_size))
        if manifest.get("version") != expected_version:
            raise ValueError(
                f"payload version {manifest.get('version')!r} != {expected_version!r}"
            )
        if manifest.get("name") != "antigravity":
            raise ValueError("upstream application name changed")
        if manifest.get("productName") != "Antigravity":
            raise ValueError("upstream profile/protocol identity changed")
        if manifest.get("desktopName", "antigravity.desktop") != "antigravity.desktop":
            raise ValueError("upstream desktop identity changed")
        main = manifest.get("main")
        if not isinstance(main, str) or not main:
            raise ValueError("missing application entry point")
        main_entry = entry_for(main)
        if main_entry.get("unpacked"):
            unpacked = payload / "resources/app.asar.unpacked" / main
            if not unpacked.is_file():
                raise ValueError("missing unpacked application entry point")
        else:
            packed_range(main_entry)


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: validate-payload.py PAYLOAD VERSION", file=sys.stderr)
        return 2
    try:
        validate(Path(sys.argv[1]), sys.argv[2])
    except (OSError, ValueError, KeyError, TypeError, struct.error) as error:
        print(f"Antigravity payload validation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
