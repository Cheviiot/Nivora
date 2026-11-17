#!/bin/bash
# Reconcile an exact-SHA verification result with the current main branch.
set -euo pipefail

mode="${1:?usage: reconcile_updater_pause.sh (success|failure) sha}"
requested_sha="${2:?verification SHA is required}"
case "$mode" in
success | failure) ;;
*) echo "Invalid verification result: $mode" >&2; exit 2 ;;
esac
[[ "$requested_sha" =~ ^[0-9a-f]{40}$ ]] || {
    echo "Invalid verification SHA: $requested_sha" >&2
    exit 2
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
cd "$repo_root"

git_args=(-c http.connectTimeout=90 -c http.lowSpeedLimit=20 -c http.lowSpeedTime=90 -c http.version=HTTP/1.1)
remote_url="$(git remote get-url origin)"
if [[ "$remote_url" =~ ^https://github\.com/ ]]; then
    [[ -n "${GH_TOKEN:-}" ]] || {
        echo 'reconcile_updater_pause: GH_TOKEN is required for GitHub fetches' >&2
        exit 2
    }
    auth_header="$(printf 'x-access-token:%s' "$GH_TOKEN" | base64 | tr -d '\n')"
    git_args+=(-c "http.https://github.com/.extraheader=AUTHORIZATION: basic ${auth_header}")
fi

timeout 90s git "${git_args[@]}" fetch --no-tags origin \
    +refs/heads/main:refs/remotes/origin/main >&2
current_main="$(git rev-parse refs/remotes/origin/main)"

if [[ "$mode" == failure ]]; then
    if git merge-base --is-ancestor "$requested_sha" "$current_main"; then
        "$script_dir/set_updater_pause.sh" true "$current_main" \
            "post-push validation failed for ancestor ${requested_sha}"
        printf 'action=paused\nsha=%s\n' "$current_main"
    else
        printf 'action=none\nreason=failed-sha-not-ancestor\n'
    fi
    exit 0
fi

# A successful old run cannot clear a pause on a newer main. This is a safe
# no-op, not a failed gate: the next scheduled recovery verifies the new SHA.
if [[ "$current_main" != "$requested_sha" ]]; then
    printf 'action=none\nreason=main-advanced\n'
    exit 0
fi

pause_state="$("$script_dir/get_updater_pause.sh")"
if [[ "$(jq -r .paused <<<"$pause_state")" != true ]]; then
    printf 'action=none\nreason=already-unpaused\n'
    exit 0
fi
paused_sha="$(jq -r .sha <<<"$pause_state")"
[[ "$paused_sha" =~ ^[0-9a-f]{40}$ ]] || {
    echo 'reconcile_updater_pause: paused issue has a malformed SHA' >&2
    exit 2
}
if ! git merge-base --is-ancestor "$paused_sha" "$requested_sha"; then
    printf 'action=none\nreason=pause-sha-not-ancestor\n'
    exit 0
fi

"$script_dir/set_updater_pause.sh" false "$requested_sha"
printf 'action=resumed\nsha=%s\n' "$requested_sha"
