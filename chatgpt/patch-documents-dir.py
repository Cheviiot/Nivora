"""Use the desktop Documents directory for local projectless Codex tasks."""

import hashlib
import json
import mmap
import re
import stat
import struct
import sys
import tempfile
from pathlib import Path


# This desktop-only store provides the root to local task creation, automation,
# and the folder picker. Remote hosts use the separate upstream path resolver.
EFFECTIVE_SETTING = re.compile(
    rb"getEffective\((?P<key>[\w$]+)\)\{return this\.get\((?P=key)\)\?\?"
    rb"(?P<default>\(0,[\w$]+\.[\w$]+\)\((?P=key)\)\.default)\}"
)


def documents_default(match):
    key = match["key"]
    return (
        b"getEffective(" + key + b"){return this.get(" + key + b")??("
        b'"linux"===process.platform&&"projectlessWorkspaceRoot"===' + key
        + b'?require("node:path").join(require("electron").app.getPath("documents"),"Codex")'
        + b":" + match["default"] + b")}"
    )


def packed_files(directory):
    for entry in directory["files"].values():
        if "files" in entry:
            yield from packed_files(entry)
        elif "offset" in entry:
            yield entry


def patch_archive(path):
    mode = stat.S_IMODE(path.stat().st_mode)
    with path.open("rb") as source, mmap.mmap(source.fileno(), 0, access=mmap.ACCESS_READ) as archive:
        _, header_size, _, json_size = struct.unpack_from("<IIII", archive)
        directory = json.loads(archive[16:16 + json_size])
        payload_start = 8 + header_size
        build = directory["files"][".vite"]["files"]["build"]["files"]
        targets = []
        for name, entry in build.items():
            if not name.startswith("early-bootstrap") or not name.endswith(".js") or "offset" not in entry:
                continue
            offset = int(entry["offset"])
            start = payload_start + offset
            original = archive[start:start + entry["size"]]
            if b'"settings-store"' not in original or b"projectlessWorkspaceRoot" not in original:
                continue
            patched, count = EFFECTIVE_SETTING.subn(documents_default, original)
            if count:
                targets.append((count, entry, offset, patched))

        if len(targets) != 1 or targets[0][0] != 1:
            raise ValueError("expected exactly one upstream desktop settings resolver")

        _, entry, offset, patched = targets[0]
        start = payload_start + offset
        end = start + entry["size"]
        delta = len(patched) - entry["size"]
        for other in packed_files(directory):
            if int(other["offset"]) >= end - payload_start:
                other["offset"] = str(int(other["offset"]) + delta)
        entry["size"] = len(patched)
        integrity = entry["integrity"]
        block_size = integrity["blockSize"]
        if integrity["algorithm"] != "SHA256" or block_size <= 0:
            raise ValueError("unsupported upstream ASAR integrity metadata")
        integrity["hash"] = hashlib.sha256(patched).hexdigest()
        integrity["blocks"] = [
            hashlib.sha256(patched[i:i + block_size]).hexdigest()
            for i in range(0, len(patched), block_size)
        ]

        header = json.dumps(directory, separators=(",", ":")).encode()
        padded_size = (len(header) + 3) & ~3
        with tempfile.TemporaryDirectory(dir=path.parent) as temporary:
            staged = Path(temporary) / path.name
            with staged.open("wb") as output, memoryview(archive) as payload:
                output.write(struct.pack("<IIII", 4, padded_size + 8, padded_size + 4, len(header)))
                output.write(header)
                output.write(bytes(padded_size - len(header)))
                output.write(payload[payload_start:start])
                output.write(patched)
                output.write(payload[end:])
            staged.chmod(mode)
            staged.replace(path)


if __name__ == "__main__":
    try:
        patch_archive(Path(sys.argv[1]))
    except (KeyError, OSError, ValueError, struct.error) as error:
        raise SystemExit(f"ChatGPT ASAR: {error}") from error
