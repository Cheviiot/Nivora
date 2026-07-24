#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
recipe="${repo_root}/codex/Staplerfile"
driver="${repo_root}/codex/patch-computer-use.js"

grep -Fq 'release=1' "$recipe"
grep -Fq '15f3bd4fabc44bc0afba85b16d0121f0b4abd052' "$recipe"
grep -Fq 'computer-use-linux/archive/refs/tags/v0.4.1.tar.gz' "$recipe"
grep -Fq 'cargo build' "$recipe"
grep -Fq 'CODEX_LINUX_ENABLE_COMPUTER_USE_UI = "1"' "$driver"
grep -Fq 'applyLinuxComputerUseHostPlatformPatch' "$driver"
grep -Fq 'applyLinuxComputerUseInstallFlowPatch' "$driver"
grep -Fq 'codexLinuxNativeDesktopApps(' "$driver"
grep -Fq 'codexLinuxRegisterComputerUseCursorHandler' "$driver"
grep -Fq 'isHostCompatiblePlatform:' "$driver"
grep -Fq 'computer-use@openai-bundled' "${repo_root}/docs/packages/codex.md"

python3 - "$repo_root" <<'PY'
import hashlib
import importlib.util
import json
import struct
import sys
import tempfile
from pathlib import Path

root = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location(
    "asar_tree", root / "codex" / "asar_tree.py"
)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

with tempfile.TemporaryDirectory() as temporary:
    work = Path(temporary)
    content = b"upstream Codex fixture\n"
    digest = hashlib.sha256(content).hexdigest()
    header = {
        "files": {
            "fixture.txt": {
                "size": len(content),
                "offset": "0",
                "integrity": {
                    "algorithm": "SHA256",
                    "hash": digest,
                    "blockSize": 4194304,
                    "blocks": [digest],
                },
            }
        }
    }
    encoded = json.dumps(header, separators=(",", ":")).encode()
    padded = module.align4(len(encoded))
    payload_size = 4 + padded
    archive = work / "fixture.asar"
    archive.write_bytes(
        struct.pack("<IIII", 4, 4 + payload_size, payload_size, len(encoded))
        + encoded
        + b"\0" * (padded - len(encoded))
        + content
    )
    extracted = work / "tree"
    rebuilt = work / "rebuilt.asar"
    module.extract(archive, extracted)
    module.rebuild(archive, extracted, rebuilt)
    assert rebuilt.read_bytes() == archive.read_bytes()

print("OK: Codex Computer Use использует закреплённую upstream-реализацию")
PY
