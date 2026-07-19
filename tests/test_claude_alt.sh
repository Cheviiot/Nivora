#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
launcher="${repo_root}/claude-desktop/claude-alt"
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

echo 'OK: ClaudeAlt launcher'
