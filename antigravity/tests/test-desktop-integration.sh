#!/bin/bash
# Exercise the installed launcher's argument and environment boundary without
# starting Electron or writing to the real /opt installation.
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temp_dir="$(mktemp -d)"
cleanup() {
    find "$temp_dir" -mindepth 1 -delete
    rmdir "$temp_dir"
}
trap cleanup EXIT

ANTIGRAVITY_TEST_RESULT="${temp_dir}/result.json" \
ANTIGRAVITY_TEST_LAUNCHER="${package_dir}/antigravity-launcher" \
ELECTRON_RUN_AS_NODE=1 APPIMAGE=/tmp/unrelated.AppImage APPDIR=/tmp/unrelated \
CHROME_DESKTOP=unrelated.desktop \
    bash -euo pipefail -c '
        exec() {
            python3 - "$@" <<"PY"
import json
import os
import sys
from pathlib import Path

Path(os.environ["ANTIGRAVITY_TEST_RESULT"]).write_text(json.dumps({
    "argv": sys.argv[1:],
    "desktop": os.environ.get("CHROME_DESKTOP"),
    "inherited": {
        key: os.environ[key]
        for key in ("ELECTRON_RUN_AS_NODE", "APPIMAGE", "APPDIR")
        if key in os.environ
    },
}), encoding="utf-8")
PY
        }
        # shellcheck disable=SC1090
        source "$ANTIGRAVITY_TEST_LAUNCHER" "$@"
    ' launcher -- \
    'antigravity://oauth-success?state=a%20b&code=literal;$HOME' \
    'a path with spaces' ''

python3 - "${temp_dir}/result.json" <<'PY'
import json
import sys
from pathlib import Path

result = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert result["argv"] == [
    "/opt/antigravity/antigravity", "--",
    "antigravity://oauth-success?state=a%20b&code=literal;$HOME",
    "a path with spaces", "",
], result
assert result["desktop"] == "antigravity.desktop", result
assert result["inherited"] == {}, result
PY

echo 'OK: Antigravity launcher preserves arguments and isolates Electron environment'
