#!/bin/bash
set -euo pipefail

# Fixture publishers must never write into a live updater's diagnostics directory.
unset AUTONOMOUS_UPDATE_RESULTS_DIR

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/nivora-pause-preflight.XXXXXX")"
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
    local dir="$scratch/$1"
    mkdir -p "$dir/bin"
    git init --bare -q "$dir/remote.git"
    git --git-dir="$dir/remote.git" symbolic-ref HEAD refs/heads/main
    git clone -q "$dir/remote.git" "$dir/repo"
    git -C "$dir/repo" checkout -qb main
    git -C "$dir/repo" config user.name "$GIT_AUTHOR_NAME"
    git -C "$dir/repo" config user.email "$GIT_AUTHOR_EMAIL"
    mkdir -p "$dir/repo/.github/tools" "$dir/repo/demo"
    printf '# Test package catalog\n' >"$dir/repo/README.md"
    printf "name='demo'\nversion='1.0'\nrelease=1\n" >"$dir/repo/demo/Staplerfile"
    local old_date
    old_date="$(date -u -d '31 days ago' '+%Y-%m-%dT%H:%M:%S +0000')"
    GIT_AUTHOR_DATE="$old_date" GIT_COMMITTER_DATE="$old_date" \
        git -C "$dir/repo" add README.md demo/Staplerfile
    GIT_AUTHOR_DATE="$old_date" GIT_COMMITTER_DATE="$old_date" \
        git -C "$dir/repo" commit -qm 'old main'
    git -C "$dir/repo" push -q -u origin main
    cp "$repo_root/.github/tools/updater_pause_preflight.sh" "$dir/repo/.github/tools/"
    cp "$repo_root/.github/tools/get_updater_pause.sh" "$dir/repo/.github/tools/"
    cp "$repo_root/.github/tools/plan_updater_recovery.py" "$dir/repo/.github/tools/"
    cp "$repo_root/.github/tools/publish_update_commit.sh" "$dir/repo/.github/tools/"
    cp "$repo_root/.github/tools/maintenance_heartbeat.py" "$dir/repo/.github/tools/"
    cat >"$dir/bin/gh" <<'GH'
#!/bin/bash
set -euo pipefail
if [[ "$1" == api && "$*" == *'/issues?'* ]]; then
    cat "$GH_PAUSE_ISSUE_FILE"
elif [[ "$1" == api && "$*" == *'/actions/workflows/post-push-verify.yml/runs?'* ]]; then
    cat "$GH_RUNS_FILE"
elif [[ "$1" == workflow && "$2" == run ]]; then
    sha=''
    while (($#)); do
        case "$1" in
            -f) shift; [[ "$1" == sha=* ]] && sha="${1#sha=}" ;;
        esac
        shift || true
    done
    printf '%s\n' "$sha" >>"$GH_DISPATCH_LOG"
else
    echo "unexpected gh invocation: $*" >&2
    exit 1
fi
GH
    chmod +x "$dir/bin/gh"
    printf '%s\n' "$dir/repo"
}

write_pause_issue() {
    local file="$1" sha="$2"
    cat >"$file" <<JSON
[[{"number":12,"title":"[autoupdate] обновления приостановлены","body":"<!-- nivora-updater-paused -->\n<!-- nivora-updater-paused-sha: ${sha} -->\n","user":{"login":"github-actions[bot]"}}]]
JSON
}

write_runs() {
    local file="$1" json="$2"
    printf '%s\n' "$json" >"$file"
}

run_preflight() {
    local repo="$1" case_dir="${1%/repo}"
    (cd "$repo" && PATH="$case_dir/bin:$PATH" \
        GITHUB_REPOSITORY='owner/repo' GITHUB_RUN_ID=123 \
        GH_PAUSE_ISSUE_FILE="$case_dir/pause-issue.json" \
        GH_RUNS_FILE="$case_dir/runs.json" \
        GH_DISPATCH_LOG="$case_dir/dispatched" \
        GITHUB_OUTPUT="$case_dir/output" \
        BASH_ENV=/dev/null .github/tools/updater_pause_preflight.sh)
}

assert_paused_true() {
    grep -Fxq 'paused=true' "$1"
}

main_ref() {
    git --git-dir="${1%/repo}/remote.git" rev-parse refs/heads/main
}

# An active recovery keeps its exact SHA and must suppress heartbeat publication.
repo="$(new_case active)"
case_dir="${repo%/repo}"
base="$(git -C "$repo" rev-parse HEAD)"
write_pause_issue "$case_dir/pause-issue.json" "$base"
write_runs "$case_dir/runs.json" "{\"workflow_runs\":[{\"display_title\":\"post-push ${base} · updater 12345 · resume true\",\"status\":\"in_progress\",\"conclusion\":null,\"created_at\":\"2026-10-01T00:00:00Z\"}]}"
run_preflight "$repo"
assert_paused_true "$case_dir/output"
[[ "$(main_ref "$repo")" == "$base" ]]
[[ ! -e "$case_dir/dispatched" ]]

# A paused old main gets one empty heartbeat, then recovery is planned for its new SHA.
repo="$(new_case old-paused)"
case_dir="${repo%/repo}"
base="$(git -C "$repo" rev-parse HEAD)"
write_pause_issue "$case_dir/pause-issue.json" "$base"
write_runs "$case_dir/runs.json" '{"workflow_runs":[]}'
run_preflight "$repo"
assert_paused_true "$case_dir/output"
new_sha="$(main_ref "$repo")"
[[ "$new_sha" != "$base" ]]
[[ "$(git --git-dir="$case_dir/remote.git" show -s --format=%s "$new_sha")" == 'chore: keep autonomous maintenance active' ]]
[[ "$(<"$case_dir/dispatched")" == "$new_sha" ]]
[[ "$(git --git-dir="$case_dir/remote.git" show "$new_sha:demo/Staplerfile")" == "$(git --git-dir="$case_dir/remote.git" show "$base:demo/Staplerfile")" ]]

# A completed failure within cooldown is replanned only after publishing; the dispatch uses the new SHA.
repo="$(new_case cooldown)"
case_dir="${repo%/repo}"
base="$(git -C "$repo" rev-parse HEAD)"
write_pause_issue "$case_dir/pause-issue.json" "$base"
recent="$(date -u -d '5 minutes ago' '+%Y-%m-%dT%H:%M:%SZ')"
write_runs "$case_dir/runs.json" "{\"workflow_runs\":[{\"display_title\":\"post-push ${base} · updater 12345 · resume true\",\"status\":\"completed\",\"conclusion\":\"failure\",\"created_at\":\"2026-10-01T00:00:00Z\",\"updated_at\":\"${recent}\"}]}"
run_preflight "$repo"
new_sha="$(main_ref "$repo")"
[[ "$new_sha" != "$base" ]]
[[ "$(<"$case_dir/dispatched")" == "$new_sha" ]]

# If main races to a history that no longer contains pause SHA, do not dispatch recovery.
repo="$(new_case stale-remote)"
case_dir="${repo%/repo}"
base="$(git -C "$repo" rev-parse HEAD)"
write_pause_issue "$case_dir/pause-issue.json" "$base"
write_runs "$case_dir/runs.json" '{"workflow_runs":[]}'
git init -q "$case_dir/racer"
git -C "$case_dir/racer" checkout -qb stale-history
git -C "$case_dir/racer" config user.name "$GIT_AUTHOR_NAME"
git -C "$case_dir/racer" config user.email "$GIT_AUTHOR_EMAIL"
printf 'rewritten main\n' >"$case_dir/racer/README.md"
git -C "$case_dir/racer" add README.md
git -C "$case_dir/racer" commit -qm 'unrelated replacement history'
git -C "$case_dir/racer" remote add origin "$case_dir/remote.git"
git -C "$case_dir/racer" push -q origin HEAD:stale-history
stale_sha="$(git -C "$case_dir/racer" rev-parse HEAD)"
mkdir -p "$repo/.git/hooks"
cat >"$repo/.git/hooks/pre-push" <<EOF
#!/bin/sh
git --git-dir='$case_dir/remote.git' update-ref refs/heads/main '$stale_sha'
EOF
chmod +x "$repo/.git/hooks/pre-push"
run_preflight "$repo"
assert_paused_true "$case_dir/output"
[[ "$(main_ref "$repo")" == "$stale_sha" ]]
[[ ! -e "$case_dir/dispatched" ]]

echo 'OK: paused updater heartbeat preserves active gates and rechecks refreshed main'
