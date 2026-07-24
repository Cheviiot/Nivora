#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import struct
import sys
from pathlib import Path


UPSTREAM_RESOURCES = {
    "idle": (
        "c0939b3a81a59983f0db07cdfa08eae90d6ddc211b7b790c425beb72628355ea",
        b'<svg width="64" height="64"',
    ),
    "connected": (
        "5e1703683c6263b5a2cdda83b034dec23fe31e72497f6644a3853b97c6fdef85",
        b'<svg width="15" height="15"',
    ),
}


def replace_resource(
    binary: bytearray,
    kind: str,
    replacement: bytes,
    expected_start: int | None = None,
) -> tuple[int, int]:
    expected_hash, marker = UPSTREAM_RESOURCES[kind]
    matches: list[tuple[int, int]] = []
    offset = 0

    while True:
        start = binary.find(marker, offset)
        if start < 0:
            break
        offset = start + 1
        if start < 4:
            continue

        length = struct.unpack_from(">I", binary, start - 4)[0]
        if length <= 0 or start + length > len(binary):
            continue
        payload = bytes(binary[start:start + length])
        if (
            hashlib.sha256(payload).hexdigest() == expected_hash
            and (expected_start is None or start == expected_start)
        ):
            matches.append((start, length))

    if len(matches) != 1:
        raise RuntimeError(
            f"expected exactly one upstream {kind} tray resource, found {len(matches)}"
        )

    start, capacity = matches[0]
    if len(replacement) > capacity:
        raise RuntimeError(
            f"{kind} tray replacement is too large: {len(replacement)} > {capacity}"
        )

    struct.pack_into(">I", binary, start - 4, len(replacement))
    binary[start:start + len(replacement)] = replacement
    binary[start + len(replacement):start + capacity] = b"\0" * (
        capacity - len(replacement)
    )
    return start, capacity


def main() -> int:
    if len(sys.argv) != 4:
        print(
            "usage: patch-tray-icons.py <Happ binary> <idle.svg> <connected.svg>",
            file=sys.stderr,
        )
        return 2

    binary_path = Path(sys.argv[1])
    binary = bytearray(binary_path.read_bytes())
    connected_start, connected_capacity = replace_resource(
        binary, "connected", Path(sys.argv[3]).read_bytes()
    )
    replace_resource(
        binary,
        "idle",
        Path(sys.argv[2]).read_bytes(),
        connected_start + connected_capacity + 4,
    )
    binary_path.write_bytes(binary)
    print("Patched Happ tray icons")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
