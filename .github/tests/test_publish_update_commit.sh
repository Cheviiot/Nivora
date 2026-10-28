#!/bin/bash
set -euo pipefail

# Fixture publishers must never write into a live updater's diagnostics directory.
unset AUTONOMOUS_UPDATE_RESULTS_DIR

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/nivora-publish-test.XXXXXX")"
cleanup() {
    find "$scratch" -mindepth 1 -delete
    rmdir "$scratch"
}
trap cleanup EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_TERMINAL_PROMPT=0
export GIT_AUTHOR_NAME='github-actions[bot]'
export GIT_AUTHOR_EMAIL='41898282+github-actions[bot]@users.noreply.github.com'
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"

new_case() {
    local name="$1"
    local dir="$scratch/$name"
    mkdir -p "$dir"
    git init --bare -q "$dir/remote.git"
    git --git-dir="$dir/remote.git" symbolic-ref HEAD refs/heads/main
    git clone -q "$dir/remote.git" "$dir/repo"
    git -C "$dir/repo" checkout -qb main
    git -C "$dir/repo" config user.name "$GIT_AUTHOR_NAME"
    git -C "$dir/repo" config user.email "$GIT_AUTHOR_EMAIL"
    mkdir -p "$dir/repo/demo" "$dir/repo/.github/tools"
    printf '# Demo\n' >"$dir/repo/README.md"
    printf 'name: demo\nversion: 1\n' >"$dir/repo/demo/Staplerfile"
    git -C "$dir/repo" add README.md demo/Staplerfile
    git -C "$dir/repo" commit -qm initial
    git -C "$dir/repo" push -q -u origin main
    cp "$repo_root/.github/tools/publish_update_commit.sh" "$dir/repo/.github/tools/"
    cp "$repo_root/.github/tools/maintenance_heartbeat.py" "$dir/repo/.github/tools/"
    printf '%s\n' "$dir/repo"
}

invoke() {
    local repo="$1" base="$2"
    (cd "$repo" && EXPECTED_BASE_SHA="$base" SUCCESSFUL_PACKAGES='["demo"]' \
        .github/tools/publish_update_commit.sh)
}

assert_fields() {
    local output="$1" expected_pushed="$2" expected_reason="$3"
    grep -Fxq "pushed=$expected_pushed" <<<"$output"
    grep -Fxq "reason=$expected_reason" <<<"$output"
}

# Fresh no-op does not create a commit or push.
repo="$(new_case fresh)"
base="$(git -C "$repo" rev-parse HEAD)"
cat >"$repo/.git/hooks/pre-push" <<EOF
#!/bin/sh
touch '$scratch/unexpected-noop-push'
exit 99
EOF
chmod +x "$repo/.git/hooks/pre-push"
out="$(invoke "$repo" "$base")"
assert_fields "$out" false no-changes
[[ "$(git -C "$repo" rev-parse HEAD)" == "$base" ]]
[[ "$(git --git-dir="${repo%/repo}/remote.git" rev-parse refs/heads/main)" == "$base" ]]
[[ ! -e "$scratch/unexpected-noop-push" ]]

# A recipe update creates and publishes only the allowed recipe/catalog changes.
repo="$(new_case update)"
base="$(git -C "$repo" rev-parse HEAD)"
printf 'name: demo\nversion: 2\n' >"$repo/demo/Staplerfile"
printf 'untracked\n' >"$repo/extra.txt"
out="$(invoke "$repo" "$base")"
assert_fields "$out" true update
published="$(git -C "$repo" rev-parse HEAD)"
[[ "$(git --git-dir="${repo%/repo}/remote.git" rev-parse refs/heads/main)" == "$published" ]]
[[ "$(git -C "$repo" show --pretty=format: --name-only HEAD | sort -u)" == demo/Staplerfile ]]
[[ -f "$repo/extra.txt" ]]

# A checkout that is already beyond the caller's expected base is untouched.
repo="$(new_case local-advanced)"
base="$(git -C "$repo" rev-parse HEAD)"
printf 'local\n' >>"$repo/README.md"
git -C "$repo" add README.md
git -C "$repo" commit -qm 'advance local checkout'
local_head="$(git -C "$repo" rev-parse HEAD)"
out="$(invoke "$repo" "$base")"
assert_fields "$out" false main-advanced
[[ "$(git -C "$repo" rev-parse HEAD)" == "$local_head" ]]

# A remote advance before the helper runs is detected after its ordinary push is rejected.
repo="$(new_case remote-advanced)"
base="$(git -C "$repo" rev-parse HEAD)"
git clone -q "${repo%/repo}/remote.git" "${repo%/repo}/other"
git -C "${repo%/repo}/other" config user.name "$GIT_AUTHOR_NAME"
git -C "${repo%/repo}/other" config user.email "$GIT_AUTHOR_EMAIL"
printf 'external\n' >>"${repo%/repo}/other/README.md"
git -C "${repo%/repo}/other" commit -qam external
git -C "${repo%/repo}/other" push -q origin HEAD:main
external_head="$(git --git-dir="${repo%/repo}/remote.git" rev-parse refs/heads/main)"
printf 'name: demo\nversion: 2\n' >"$repo/demo/Staplerfile"
out="$(invoke "$repo" "$base")"
assert_fields "$out" false main-advanced
[[ "$(git --git-dir="${repo%/repo}/remote.git" rev-parse refs/heads/main)" == "$external_head" ]]

# A pre-push hook advances main between the local base check and push.
repo="$(new_case push-race)"
base="$(git -C "$repo" rev-parse HEAD)"
git clone -q "${repo%/repo}/remote.git" "${repo%/repo}/racer"
git -C "${repo%/repo}/racer" config user.name "$GIT_AUTHOR_NAME"
git -C "${repo%/repo}/racer" config user.email "$GIT_AUTHOR_EMAIL"
printf 'race\n' >>"${repo%/repo}/racer/README.md"
git -C "${repo%/repo}/racer" commit -qam race
git -C "${repo%/repo}/racer" push -q origin HEAD:race-object
race_sha="$(git -C "${repo%/repo}/racer" rev-parse HEAD)"
git --git-dir="${repo%/repo}/remote.git" update-ref refs/heads/main "$base"
mkdir -p "$repo/.git/hooks"
cat >"$repo/.git/hooks/pre-push" <<EOF
#!/bin/sh
git --git-dir='${repo%/repo}/remote.git' update-ref refs/heads/main '$race_sha'
EOF
chmod +x "$repo/.git/hooks/pre-push"
printf 'name: demo\nversion: 2\n' >"$repo/demo/Staplerfile"
out="$(invoke "$repo" "$base")"
assert_fields "$out" false main-advanced
[[ "$(git --git-dir="${repo%/repo}/remote.git" rev-parse refs/heads/main)" == "$race_sha" ]]

# A successful remote update whose acknowledgement was lost is still a push.
# A subsequent fast-forward must not hide that publication from post-push CI.
real_git="$(command -v git)"
mock_bin="$scratch/lost-ack-bin"
mkdir -p "$mock_bin"
cat >"$mock_bin/git" <<'MOCK'
#!/bin/bash
set -euo pipefail
is_push=false
for argument in "$@"; do
    [[ "$argument" != push ]] || is_push=true
done
if [[ "$is_push" == true && "$PWD" == "${TEST_LOST_ACK_REPO:?}" ]]; then
    "${TEST_REAL_GIT:?}" "$@"
    if [[ "${TEST_FAST_FORWARD:-0}" == 1 ]]; then
        "${TEST_REAL_GIT}" clone -q "${TEST_REMOTE:?}" "${TEST_SUCCESSOR:?}"
        printf 'successor\n' >>"${TEST_SUCCESSOR}/README.md"
        "${TEST_REAL_GIT}" -C "$TEST_SUCCESSOR" commit -qam successor
        "${TEST_REAL_GIT}" -C "$TEST_SUCCESSOR" push -q origin HEAD:main
    fi
    exit 1
fi
exec "${TEST_REAL_GIT:?}" "$@"
MOCK
chmod +x "$mock_bin/git"
for fast_forward in 0 1; do
    repo="$(new_case "lost-ack-${fast_forward}")"
    base="$(git -C "$repo" rev-parse HEAD)"
    printf 'name: demo\nversion: 2\n' >"$repo/demo/Staplerfile"
    results="${repo%/repo}/results"
    out="$(PATH="$mock_bin:$PATH" TEST_REAL_GIT="$real_git" \
        TEST_LOST_ACK_REPO="$repo" TEST_FAST_FORWARD="$fast_forward" \
        TEST_REMOTE="${repo%/repo}/remote.git" TEST_SUCCESSOR="${repo%/repo}/successor" \
        AUTONOMOUS_UPDATE_RESULTS_DIR="$results" invoke "$repo" "$base")"
    assert_fields "$out" true update
    published="$(git -C "$repo" rev-parse HEAD)"
    grep -Fxq "sha=$published" <<<"$out"
    [[ "$(cat "$results/pushed-sha")" == "$published" ]]
    remote_head="$(git --git-dir="${repo%/repo}/remote.git" rev-parse main)"
    git --git-dir="${repo%/repo}/remote.git" merge-base --is-ancestor "$published" "$remote_head"
    if [[ "$fast_forward" == 1 ]]; then
        [[ "$remote_head" != "$published" ]]
    fi
done

# An old base gets exactly one empty heartbeat; its new HEAD is fresh.
repo="$(new_case heartbeat)"
base="$(git -C "$repo" rev-parse HEAD)"
old_date="$(date -u -d '31 days ago' '+%Y-%m-%dT%H:%M:%S +0000')"
GIT_AUTHOR_DATE="$old_date" GIT_COMMITTER_DATE="$old_date" \
    git -C "$repo" commit --allow-empty -qm 'old baseline'
old_base="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" push -q origin HEAD:main
out="$(invoke "$repo" "$old_base")"
assert_fields "$out" true heartbeat
heartbeat_sha="$(git -C "$repo" rev-parse HEAD)"
[[ "$(git --git-dir="${repo%/repo}/remote.git" rev-parse refs/heads/main)" == "$heartbeat_sha" ]]
out="$(invoke "$repo" "$heartbeat_sha")"
assert_fields "$out" false no-changes

# Unknown staged content is never included in an autonomous commit.
repo="$(new_case foreign-staged)"
base="$(git -C "$repo" rev-parse HEAD)"
printf 'foreign\n' >"$repo/foreign.txt"
git -C "$repo" add foreign.txt
if invoke "$repo" "$base" >"$scratch/foreign.out" 2>"$scratch/foreign.err"; then
    echo 'helper accepted a foreign staged file' >&2
    exit 1
fi
[[ "$(git -C "$repo" rev-parse HEAD)" == "$base" ]]
[[ "$(git -C "$repo" diff --cached --name-only)" == foreign.txt ]]

echo 'OK: publication checks base, stages an allowlist, and preserves concurrent main updates'
