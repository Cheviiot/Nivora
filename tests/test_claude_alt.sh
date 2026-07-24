#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
launcher="${repo_root}/claude-desktop/claude-alt"
icon="${repo_root}/claude-desktop/claude-alt.png"
primary_tray_icon="${repo_root}/claude-desktop/claude-tray-orange.png"
alternate_tray_icon="${repo_root}/claude-desktop/claude-alt-tray-turquoise.png"
temp_dir="$(mktemp -d)"

cleanup() {
    find "$temp_dir" -mindepth 1 -delete
    rmdir "$temp_dir"
}
trap cleanup EXIT

mkdir -p "${temp_dir}/bin" "${temp_dir}/home"
log="${temp_dir}/launch.log"

cat >"${temp_dir}/bin/claude-alt-bin" <<'EOF'
#!/bin/sh
set -eu
printf 'desktop=%s\n' "${CHROME_DESKTOP:-}" >"$NIVORA_TEST_LOG"
printf 'arg=%s\n' "$@" >>"$NIVORA_TEST_LOG"
EOF
chmod 0755 "${temp_dir}/bin/claude-alt-bin"

export HOME="${temp_dir}/home"
export CLAUDE_ALT_EXECUTABLE="${temp_dir}/bin/claude-alt-bin"
export NIVORA_TEST_LOG="$log"

unset XDG_CONFIG_HOME CLAUDE_ALT_DATA_DIR CLAUDE_DESKTOP_ACCOUNT2_DIR
"$launcher" 'claude://claude.ai/new'
grep -Fxq 'desktop=com.anthropic.ClaudeAlt.desktop' "$log"
grep -Fxq "arg=--user-data-dir=${HOME}/.config/ClaudeAlt" "$log"
grep -Fxq 'arg=--class=com.anthropic.ClaudeAlt' "$log"
grep -Fxq 'arg=claude://claude.ai/new' "$log"
test -d "${HOME}/.config/ClaudeAlt"

legacy_config="${temp_dir}/legacy-config"
mkdir -p "${legacy_config}/Claude-Account-2"
export XDG_CONFIG_HOME="$legacy_config"
"$launcher"
grep -Fxq "arg=--user-data-dir=${legacy_config}/Claude-Account-2" "$log"

explicit_profile="${temp_dir}/explicit-profile"
export CLAUDE_ALT_DATA_DIR="$explicit_profile"
"$launcher"
grep -Fxq "arg=--user-data-dir=${explicit_profile}" "$log"
test -d "$explicit_profile"

python3 - "$icon" "$primary_tray_icon" "$alternate_tray_icon" <<'PY'
import struct
import sys
from pathlib import Path

expected_sizes = {
    Path(sys.argv[1]): (512, 512),
    Path(sys.argv[2]): (64, 64),
    Path(sys.argv[3]): (64, 64),
}

for path, expected_size in expected_sizes.items():
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"{path.name} is not a PNG")

    width, height, bit_depth, color_type = struct.unpack(">IIBB", data[16:26])
    if (width, height) != expected_size:
        raise SystemExit(
            f"{path.name} must be {expected_size[0]}x{expected_size[1]}, "
            f"got {width}x{height}"
        )
    if bit_depth != 8 or color_type not in (4, 6):
        raise SystemExit(f"{path.name} must be an 8-bit PNG with alpha")
PY

echo 'OK: ClaudeAlt launcher'
