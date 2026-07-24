#!/usr/bin/env python3
"""Give ClaudeAlt an independent Electron identity without changing its protocol."""

import copy
import hashlib
import json
import struct
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = path.read_bytes()
if len(data) < 16:
    raise SystemExit("ClaudeAlt app.asar is too small")

_, _, _, header_size = struct.unpack("<IIII", data[:16])
header = json.loads(data[16 : 16 + header_size])
base_offset = 16 + ((header_size + 3) & ~3)
output = bytearray()
counts = {"package": 0, "socket": 0, "user_agent": 0}


def integrity(content: bytes, block_size: int) -> dict:
    blocks = [
        hashlib.sha256(content[index : index + block_size]).hexdigest()
        for index in range(0, len(content), block_size)
    ] or [hashlib.sha256(b"").hexdigest()]
    return {
        "algorithm": "SHA256",
        "hash": hashlib.sha256(content).hexdigest(),
        "blockSize": block_size,
        "blocks": blocks,
    }


def rebuild(node: dict, prefix: str = "") -> dict:
    result = {}
    for name, child in node.get("files", {}).items():
        item_path = f"{prefix}/{name}" if prefix else name
        if "files" in child:
            result[name] = {
                **{key: value for key, value in child.items() if key != "files"},
                "files": rebuild(child, item_path),
            }
            continue

        entry = copy.deepcopy(child)
        if entry.get("unpacked"):
            result[name] = entry
            continue

        offset, size = int(entry["offset"]), int(entry["size"])
        content = data[base_offset + offset : base_offset + offset + size]
        changed = False

        if item_path == "package.json":
            package = json.loads(content)
            expected = {
                "productName": "Claude",
                "desktopName": "com.anthropic.Claude.desktop",
            }
            for field, value in expected.items():
                if package.get(field) != value:
                    raise SystemExit(
                        f"unexpected Claude package.json {field}: "
                        f"{package.get(field)!r} != {value!r}"
                    )
            package["productName"] = "ClaudeAlt"
            package["desktopName"] = "com.anthropic.ClaudeAlt.desktop"
            content = (json.dumps(package, indent=2) + "\n").encode()
            counts["package"] += 1
            changed = True

        old_socket = b"claude-cowork-vm.sock"
        socket_count = content.count(old_socket)
        if socket_count:
            content = content.replace(old_socket, b"claude-alt-cowork-vm.sock")
            counts["socket"] += socket_count
            changed = True

        marker = b'P.app.isPackaged||P.app.setName("Claude");RRn();'
        marker_count = content.count(marker)
        if marker_count:
            content = content.replace(
                marker,
                b'P.app.isPackaged||P.app.setName("Claude");'
                b'P.app.userAgentFallback=P.app.userAgentFallback'
                b'.replaceAll("ClaudeAlt","Claude");RRn();',
            )
            counts["user_agent"] += marker_count
            changed = True

        entry["offset"] = str(len(output))
        if changed:
            entry["size"] = len(content)
            block_size = entry.get("integrity", {}).get("blockSize", 4194304)
            entry["integrity"] = integrity(content, block_size)
        output.extend(content)
        result[name] = entry
    return result


rebuilt_header = {"files": rebuild(header)}
if counts != {"package": 1, "socket": 1, "user_agent": 1}:
    raise SystemExit(f"unexpected ClaudeAlt patch counts: {counts}")

header_bytes = json.dumps(rebuilt_header, separators=(",", ":")).encode()
padded_size = (len(header_bytes) + 3) & ~3
patched = (
    struct.pack("<IIII", 4, padded_size + 8, padded_size + 4, len(header_bytes))
    + header_bytes
    + b"\0" * (padded_size - len(header_bytes))
    + bytes(output)
)
required = (
    b"com.anthropic.ClaudeAlt.desktop",
    b'"productName": "ClaudeAlt"',
    b'.replaceAll("ClaudeAlt","Claude")',
    b"claude-alt-cowork-vm.sock",
)
if any(patched.count(value) != 1 for value in required):
    raise SystemExit("ClaudeAlt identity verification failed")
path.write_bytes(patched)
