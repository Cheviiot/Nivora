#!/bin/bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$package_dir/patch-endpoint-setting.py" <<'PY'
import hashlib
import json
import runpy
import struct
import sys
import tempfile
from pathlib import Path

patcher = runpy.run_path(sys.argv[1])
patches = patcher["PATCHES"]
block_size = 4 * 1024 * 1024
files = {path: before for path, (before, _) in patches.items()}
bundle = "public/build/bundle.js"
files[bundle] += b" " * block_size
untouched = "public/build/bundle.js.map"
files[untouched] = b"x" * block_size + b"tail"

def blocks(content):
    return [hashlib.sha256(content[i:i + block_size]).hexdigest()
            for i in range(0, len(content), block_size)]


tree = {"files": {}}
payload = bytearray()
for path, content in files.items():
    parts = path.split("/")
    directory = tree["files"]
    for part in parts[:-1]:
        directory = directory.setdefault(part, {"files": {}})["files"]
    directory[parts[-1]] = {
        "size": len(content),
        "offset": str(len(payload)),
        "integrity": {
            "algorithm": "SHA256",
            "hash": hashlib.sha256(content).hexdigest(),
            "blockSize": block_size,
            "blocks": blocks(content),
        },
    }
    payload.extend(content)

with tempfile.TemporaryDirectory() as tmp:
    path = Path(tmp) / "app.asar"
    header = json.dumps(tree).encode()
    padded = (len(header) + 3) & ~3
    path.write_bytes(struct.pack("<IIII", 4, padded + 8, padded + 4, len(header))
                     + header.ljust(padded, b"\0") + payload)
    patcher["patch_archive"](path)
    archive = path.read_bytes()
    _, header_size, _, json_size = struct.unpack_from("<IIII", archive)
    directory = json.loads(archive[16:16 + json_size])
    for name, entry in patcher["packed_files"](directory):
        offset = 8 + header_size + int(entry["offset"])
        content = archive[offset:offset + entry["size"]]
        expected = files[name]
        if name in patches:
            expected = expected.replace(*patches[name], 1)
        assert content == expected, name
        assert entry["integrity"]["hash"] == hashlib.sha256(content).hexdigest(), name
        assert entry["integrity"]["blocks"] == blocks(content), name

    # The compiled bundle is already patched, so the original marker is gone.
    try:
        patcher["patch_archive"](path)
    except SystemExit as error:
        assert bundle in str(error), error
    else:
        raise AssertionError("accepted a bundle without its endpoint setting")
    assert path.read_bytes() == archive, "failed patch modified the archive"
PY
