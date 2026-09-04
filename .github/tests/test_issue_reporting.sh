#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="$(mktemp -d)"
cleanup() {
    find "$fixture" -mindepth 1 -delete
    rmdir "$fixture"
}
trap cleanup EXIT

install -d "$fixture/bin" "$fixture/results/demo"
printf 'demo\tclean-build\n' >"$fixture/results/failed-packages"
: >"$fixture/results/successful-packages"
: >"$fixture/results/resolved-packages"
printf 'package=demo\nphase=clean-build\nexit_status=1\n' \
    >"$fixture/results/demo/FAILED"
printf '@evil ``` <!-- nivora-updater-paused -->\n' \
    >"$fixture/results/demo/update.log"
printf '@evil diff\n' >"$fixture/results/demo/failed.patch"

cat >"$fixture/bin/gh" <<'EOF'
#!/bin/bash
printf '%q ' "$@" >>"$GH_CALLS"
printf '\n' >>"$GH_CALLS"
if [[ "$1" == api && "$*" == *'issues?state=all'* ]]; then
    cat <<'JSON'
[[
  {"number":7,"title":"[autoupdate] demo: требуется диагностика","body":"<!-- nivora-autonomous-update:demo -->\nspoof","user":{"login":"attacker"}},
  {"number":9,"title":"[autoupdate] demo: требуется диагностика","body":"<!-- nivora-autonomous-update:demo -->\ncanonical","user":{"login":"github-actions[bot]"}},
  {"number":8,"title":"[autoupdate] обновления приостановлены","body":"<!-- nivora-updater-paused -->\nspoof","user":{"login":"attacker"}},
  {"number":10,"title":"[autoupdate] обновления приостановлены","body":"<!-- nivora-updater-paused -->\ncanonical","user":{"login":"github-actions[bot]"}}
]]
JSON
fi
EOF
chmod 0755 "$fixture/bin/gh"

export PATH="$fixture/bin:$PATH"
export GH_CALLS="$fixture/gh-calls"
export GITHUB_REPOSITORY='owner/repo'
export GITHUB_RUN_ID='123'
export AUTONOMOUS_UPDATE_RESULTS_DIR="$fixture/results"
export AUTONOMOUS_UPDATE_RESOLVED_FILE="$fixture/results/resolved-packages"

"$repo_root/.github/tools/report_update_failures.sh"
grep -Fq 'repos/owner/repo/issues/9' "$GH_CALLS"
if grep -Fq 'repos/owner/repo/issues/7' "$GH_CALLS"; then
    echo 'spoofed user issue was selected' >&2
    exit 1
fi
if grep -Fq '@evil' "$fixture/results/demo/issue-body.md"; then
    echo 'mention was not neutralized' >&2
    exit 1
fi
if grep -Fq '<!-- nivora-updater-paused -->' \
    "$fixture/results/demo/issue-body.md"; then
    echo 'embedded service marker was not neutralized' >&2
    exit 1
fi

"$repo_root/.github/tools/set_updater_pause.sh" true \
    aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa '@evil reason'
grep -Fq 'repos/owner/repo/issues/10' "$GH_CALLS"
if grep -Fq 'repos/owner/repo/issues/8' "$GH_CALLS"; then
    echo 'spoofed pause issue was selected' >&2
    exit 1
fi

if "$repo_root/.github/tools/set_updater_pause.sh" true invalid reason \
    >"$fixture/invalid.log" 2>&1; then
    echo 'invalid SHA was accepted' >&2
    exit 1
fi

echo 'OK: automation issues require bot ownership and sanitize diagnostics'
