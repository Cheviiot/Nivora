"""Reload the AniDesk window when the user selects a different endpoint."""

import hashlib
import json
import struct
import sys
from pathlib import Path


PATCHES = {
    "public/build/bundle.js": (
        b"onChangeCallback:(e,t)=>{x.set(t),set(o,!0),baseSettings.restartRequired=!0}",
        b"onChangeCallback:(e,t)=>{get(n)!==t&&(x.set(t),set(o,!0),"
        b"baseSettings.restartRequired=!0,queueMicrotask(()=>location.reload()))}",
    ),
    "src/app/settings-pages/SettingsApp.svelte": (
        b"""        onChangeCallback={(e, v) => {
            endpointUrlRaw.set(v);
            restartRequired = true;
            baseSettings.restartRequired = true;
        }}
""",
        b"""        onChangeCallback={(e, v) => {
            if (endpointUrl === v) {
                return;
            }
            endpointUrlRaw.set(v);
            restartRequired = true;
            baseSettings.restartRequired = true;
            queueMicrotask(() => window.location.reload());
        }}
""",
    ),
}


def packed_files(directory, prefix=""):
    for name, entry in directory["files"].items():
        path = prefix + name
        if "files" in entry:
            yield from packed_files(entry, path + "/")
        elif "offset" in entry:
            yield path, entry


def integrity(content):
    block_size = 4 * 1024 * 1024
    return {
        "algorithm": "SHA256",
        "hash": hashlib.sha256(content).hexdigest(),
        "blockSize": block_size,
        "blocks": [
            hashlib.sha256(content[start:start + block_size]).hexdigest()
            for start in range(0, len(content), block_size)
        ],
    }


def patch_archive(path):
    archive = memoryview(path.read_bytes())
    _, header_size, _, json_size = struct.unpack_from("<IIII", archive)
    directory = json.loads(archive[16:16 + json_size].tobytes())
    payload_start = 8 + header_size
    payload = []
    next_offset = 0
    missing = set(PATCHES)

    for name, entry in packed_files(directory):
        start = payload_start + int(entry["offset"])
        content = archive[start:start + entry["size"]]
        if len(content) != entry["size"]:
            raise SystemExit(f"AniDesk ASAR: truncated file {name}")
        if name in PATCHES:
            before, after = PATCHES[name]
            original = content.tobytes()
            if original.count(before) != 1:
                raise SystemExit(f"AniDesk ASAR: expected one endpoint setting in {name}")
            content = original.replace(before, after, 1)
            entry["integrity"] = integrity(content)
            entry["size"] = len(content)
            missing.remove(name)

        entry["offset"] = str(next_offset)
        next_offset += len(content)
        payload.append(content)

    if missing:
        raise SystemExit("AniDesk ASAR: missing " + ", ".join(sorted(missing)))

    header = json.dumps(directory, separators=(",", ":")).encode()
    padded_length = (len(header) + 3) & ~3
    with path.open("wb") as output:
        output.write(struct.pack("<IIII", 4, padded_length + 8, padded_length + 4, len(header)))
        output.write(header)
        output.write(bytes(padded_length - len(header)))
        output.writelines(payload)


if __name__ == "__main__":
    patch_archive(Path(sys.argv[1]))
