#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
cd "$repo_root"

repository="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
run_id="${GITHUB_RUN_ID:?GITHUB_RUN_ID is required}"

git_args=(-c http.connectTimeout=90 -c http.lowSpeedLimit=20 -c http.lowSpeedTime=90 -c http.version=HTTP/1.1)
remote_url="$(git remote get-url origin)"
if [[ "$remote_url" =~ ^https://github\.com/ ]]; then
    [[ -n "${GH_TOKEN:-}" ]] || {
        echo 'updater_pause_preflight: GH_TOKEN is required for GitHub fetches' >&2
        exit 2
    }
    auth_header="$(printf 'x-access-token:%s' "$GH_TOKEN" | base64 | tr -d '\n')"
    git_args+=(-c "http.https://github.com/.extraheader=AUTHORIZATION: basic ${auth_header}")
fi

fetch_main() {
    timeout 90s git "${git_args[@]}" fetch --no-tags origin \
        +refs/heads/main:refs/remotes/origin/main >&2
    git checkout --detach -q refs/remotes/origin/main
}

write_paused_output() {
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        printf 'paused=%s\n' "$1" >>"$GITHUB_OUTPUT"
    fi
}

read_recovery_plan() {
    local state="$1" sha="$2" runs request
    runs="$(gh api \
        "repos/${repository}/actions/workflows/post-push-verify.yml/runs?per_page=100" |
        jq -c '.workflow_runs')"
    request="$(jq -cn \
        --argjson pause_state "$state" \
        --arg current_sha "$sha" \
        --argjson paused_sha_is_ancestor true \
        --argjson workflow_runs "$runs" \
        --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{pause_state: $pause_state, current_sha: $current_sha,
          paused_sha_is_ancestor: $paused_sha_is_ancestor,
          workflow_runs: $workflow_runs, now: $now}')"
    python3 "$script_dir/plan_updater_recovery.py" <<<"$request"
}

pause_state="$(.github/tools/get_updater_pause.sh)"
paused="$(jq -r .paused <<<"$pause_state")"
if [[ "$paused" != true ]]; then
    write_paused_output false
    exit 0
fi

# A fresh origin/main is the only SHA allowed to drive the paused recovery plan.
fetch_main
paused_sha="$(jq -r .sha <<<"$pause_state")"
current_sha="$(git rev-parse HEAD)"
if ! git merge-base --is-ancestor "$paused_sha" "$current_sha"; then
    echo "Pause SHA ${paused_sha} is not an ancestor of current main ${current_sha}; recovery remains blocked." >&2
    write_paused_output true
    exit 0
fi

initial_plan="$(read_recovery_plan "$pause_state" "$current_sha")"
initial_reason="$(jq -r .reason <<<"$initial_plan")"
if [[ "$initial_reason" == recovery-active ]]; then
    echo "Recovery skipped: recovery-active; heartbeat is deferred for ${current_sha}." >&2
    write_paused_output true
    exit 0
fi
if [[ "$initial_reason" == pause-sha-not-ancestor ]]; then
    echo "Recovery skipped: pause SHA is not an ancestor of ${current_sha}." >&2
    write_paused_output true
    exit 0
fi

# The regular publisher creates only an empty commit here. Its SHA/base checks
# and ordinary push protect against concurrent main updates.
publish_result="$(
    EXPECTED_BASE_SHA="$current_sha" \
        SUCCESSFUL_PACKAGES='[]' \
        GH_TOKEN="${GH_TOKEN:-}" \
        .github/tools/publish_update_commit.sh
)"
publish_reason="$(sed -n 's/^reason=//p' <<<"$publish_result")"
publish_pushed="$(sed -n 's/^pushed=//p' <<<"$publish_result")"
if [[ "$publish_pushed" != true && "$publish_reason" != no-changes && "$publish_reason" != main-advanced ]]; then
    echo "updater_pause_preflight: unexpected publisher result: ${publish_reason:-missing reason}" >&2
    exit 2
fi

# Refresh even after no-op: a newer main or recovery may have appeared since
# the initial plan. Re-read pause state so a manual unpause also takes effect.
fetch_main
pause_state="$(.github/tools/get_updater_pause.sh)"
if [[ "$(jq -r .paused <<<"$pause_state")" != true ]]; then
    write_paused_output false
    exit 0
fi
paused_sha="$(jq -r .sha <<<"$pause_state")"
current_sha="$(git rev-parse HEAD)"
if ! git merge-base --is-ancestor "$paused_sha" "$current_sha"; then
    echo "Pause SHA ${paused_sha} is not an ancestor of refreshed main ${current_sha}; recovery remains blocked." >&2
    write_paused_output true
    exit 0
fi

recovery="$(read_recovery_plan "$pause_state" "$current_sha")"
if [[ "$(jq -r .action <<<"$recovery")" == dispatch ]]; then
    recovery_sha="$(jq -r .sha <<<"$recovery")"
    gh workflow run post-push-verify.yml \
        --repo "$repository" \
        --ref main \
        -f sha="$recovery_sha" \
        -f updater_run_id="$run_id" \
        -f resume_on_success=true
    echo "Dispatched full post-push recovery for refreshed SHA ${recovery_sha}." >&2
else
    echo "Recovery skipped: $(jq -r .reason <<<"$recovery")." >&2
fi
write_paused_output true
