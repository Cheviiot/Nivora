#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="$(mktemp -d)"
cleanup() {
    find "$fixture" -mindepth 1 -delete
    rmdir "$fixture"
}
trap cleanup EXIT

git init --bare -q "$fixture/remote.git"
git --git-dir="$fixture/remote.git" symbolic-ref HEAD refs/heads/main
git clone -q "$fixture/remote.git" "$fixture/repo"
git -C "$fixture/repo" checkout -qb main
git -C "$fixture/repo" config user.name test
git -C "$fixture/repo" config user.email test@example.invalid
printf 'catalog\n' >"$fixture/repo/README.md"
git -C "$fixture/repo" add README.md
git -C "$fixture/repo" commit -qm base
base="$(git -C "$fixture/repo" rev-parse HEAD)"
git -C "$fixture/repo" push -q -u origin main
mkdir -p "$fixture/repo/.github/tools"
cp "$repo_root/.github/tools/reconcile_updater_pause.sh" "$fixture/repo/.github/tools/"
cat >"$fixture/repo/.github/tools/get_updater_pause.sh" <<'EOF'
#!/bin/bash
printf '%s\n' "$TEST_PAUSE_STATE"
EOF
cat >"$fixture/repo/.github/tools/set_updater_pause.sh" <<'EOF'
#!/bin/bash
printf '%s\t%s\n' "$1" "$2" >>"$TEST_PAUSE_WRITES"
exit "${TEST_PAUSE_WRITE_EXIT:-0}"
EOF
chmod 0755 "$fixture/repo/.github/tools/"*.sh
export TEST_PAUSE_WRITES="$fixture/writes"

# A normal scheduled full check succeeds even when the updater is not paused.
output="$(TEST_PAUSE_STATE='{"paused":false,"sha":""}' \
    "$fixture/repo/.github/tools/reconcile_updater_pause.sh" success "$base")"
[[ "$output" == $'action=none\nreason=already-unpaused' ]]
[[ ! -e "$TEST_PAUSE_WRITES" ]]

# A failed exact SHA pauses the current main for automatic recovery.
output="$("$fixture/repo/.github/tools/reconcile_updater_pause.sh" failure "$base")"
[[ "$output" == $'action=paused\nsha='"$base" ]]
[[ "$(cat "$TEST_PAUSE_WRITES")" == $'true\t'"$base" ]]
: >"$TEST_PAUSE_WRITES"

# Advance the remote after the verified snapshot. The successful old run must
# be a no-op and cannot clear a newer pause, even from a stale local checkout.
printf 'new catalog\n' >"$fixture/repo/README.md"
git -C "$fixture/repo" add README.md
git -C "$fixture/repo" commit -qm next
current="$(git -C "$fixture/repo" rev-parse HEAD)"
git -C "$fixture/repo" push -q origin main
git -C "$fixture/repo" checkout --detach -q "$base"
export TEST_PAUSE_STATE="{\"paused\":true,\"sha\":\"$base\"}"
output="$("$fixture/repo/.github/tools/reconcile_updater_pause.sh" success "$base")"
[[ "$output" == $'action=none\nreason=main-advanced' ]]
[[ ! -s "$TEST_PAUSE_WRITES" ]]

# The full current SHA can resume an ancestor pause; a failed ancestor still
# pauses the current main, which the recovery planner will validate in full.
output="$("$fixture/repo/.github/tools/reconcile_updater_pause.sh" success "$current")"
[[ "$output" == $'action=resumed\nsha='"$current" ]]
[[ "$(cat "$TEST_PAUSE_WRITES")" == $'false\t'"$current" ]]
: >"$TEST_PAUSE_WRITES"
output="$("$fixture/repo/.github/tools/reconcile_updater_pause.sh" failure "$base")"
[[ "$output" == $'action=paused\nsha='"$current" ]]
[[ "$(cat "$TEST_PAUSE_WRITES")" == $'true\t'"$current" ]]
: >"$TEST_PAUSE_WRITES"

# Unrelated histories cannot create or clear a pause on main.
tree="$(git -C "$fixture/repo" rev-parse 'HEAD^{tree}')"
unrelated="$(printf 'unrelated\n' | git -C "$fixture/repo" commit-tree "$tree")"
export TEST_PAUSE_STATE="{\"paused\":true,\"sha\":\"$unrelated\"}"
output="$("$fixture/repo/.github/tools/reconcile_updater_pause.sh" success "$current")"
[[ "$output" == $'action=none\nreason=pause-sha-not-ancestor' ]]
output="$("$fixture/repo/.github/tools/reconcile_updater_pause.sh" failure "$unrelated")"
[[ "$output" == $'action=none\nreason=failed-sha-not-ancestor' ]]
[[ ! -s "$TEST_PAUSE_WRITES" ]]

# Failed issue writes and failed refreshes must not claim recovery succeeded.
export TEST_PAUSE_STATE="{\"paused\":true,\"sha\":\"$base\"}"
if output="$(TEST_PAUSE_WRITE_EXIT=7 \
    "$fixture/repo/.github/tools/reconcile_updater_pause.sh" success "$current")"; then
    echo 'Issue write failure was ignored' >&2
    exit 1
else
    [[ "$?" -eq 7 && "$output" != *'action=resumed'* ]]
fi
: >"$TEST_PAUSE_WRITES"
git -C "$fixture/repo" remote set-url origin "$fixture/missing.git"
if "$fixture/repo/.github/tools/reconcile_updater_pause.sh" success "$current" \
    >"$fixture/output" 2>"$fixture/error"; then
    echo 'Failed refresh was ignored' >&2
    exit 1
fi
[[ ! -s "$TEST_PAUSE_WRITES" ]]

echo 'OK: exact-SHA reconciliation preserves freshness and ancestry'
