#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
cd "$repo_root"

output() {
    printf 'pushed=%s\nsha=%s\nreason=%s\n' "$1" "$2" "$3"
}

fail() {
    echo "publish_update_commit: $*" >&2
    exit 2
}

expected_base="${EXPECTED_BASE_SHA:-}"
[[ "$expected_base" =~ ^[0-9a-f]{40}$ ]] || fail 'EXPECTED_BASE_SHA must be a 40-character lowercase SHA'

packages_json="${SUCCESSFUL_PACKAGES:-[]}"
packages_output="$(python3 - "$packages_json" <<'PY'
import json
import re
import sys

try:
    packages = json.loads(sys.argv[1])
except json.JSONDecodeError as exc:
    raise SystemExit(f"invalid SUCCESSFUL_PACKAGES JSON: {exc}")
if not isinstance(packages, list) or any(
    not isinstance(item, str) or not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", item)
    for item in packages
):
    raise SystemExit("SUCCESSFUL_PACKAGES must be a JSON list of safe package IDs")
if len(packages) != len(set(packages)):
    raise SystemExit("SUCCESSFUL_PACKAGES contains duplicates")
for package in packages:
    print(package)
PY
)" || fail 'invalid SUCCESSFUL_PACKAGES'
packages=()
if [[ -n "$packages_output" ]]; then
    mapfile -t packages <<<"$packages_output"
fi

for package in "${packages[@]}"; do
    [[ -f "$package/Staplerfile" && ! -L "$package/Staplerfile" ]] ||
        fail "unknown package in SUCCESSFUL_PACKAGES: $package"
done

head_sha="$(git rev-parse --verify HEAD 2>/dev/null)" || fail 'cannot resolve HEAD'
if [[ "$head_sha" != "$expected_base" ]]; then
    output false "$head_sha" main-advanced
    exit 0
fi
git diff --cached --quiet || fail 'staged index is not clean'

# Only the catalog and package recipes are eligible for publication.
shopt -s nullglob
recipes=( */Staplerfile )
[[ -f README.md && ! -L README.md && ${#recipes[@]} -gt 0 ]] ||
    fail 'expected README.md and package Staplerfiles'
git add -- README.md "${recipes[@]}"

reason=update
if git diff --cached --quiet; then
    last_commit_time="$(git show -s --format=%ct HEAD)" || fail 'cannot read last commit time'
    due="$(python3 "$script_dir/maintenance_heartbeat.py" --last-commit-time "$last_commit_time")" ||
        fail 'cannot evaluate maintenance heartbeat'
    if [[ "$due" != true ]]; then
        output false "$head_sha" no-changes
        exit 0
    fi
    git config user.name 'github-actions[bot]'
    git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
    git commit --allow-empty -m 'chore: keep autonomous maintenance active' >&2 || fail 'heartbeat commit failed'
    reason=heartbeat
else
    if ((${#packages[@]})); then
        joined="$(printf '%s, ' "${packages[@]}")"
        joined="${joined%, }"
        message="chore: autonomously update ${joined}"
    else
        message='chore: autonomously update package list'
    fi
    git config user.name 'github-actions[bot]'
    git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
    git commit -m "$message" >&2 || fail 'update commit failed'
fi

published_sha="$(git rev-parse --verify HEAD 2>/dev/null)" || fail 'cannot resolve publication commit'
remote_url="$(git remote get-url origin 2>/dev/null)" || fail 'origin remote is required'

git_args=(-c http.connectTimeout=90 -c http.lowSpeedLimit=20 -c http.lowSpeedTime=90 -c http.version=HTTP/1.1)
if [[ "$remote_url" =~ ^https://github\.com/ ]]; then
    [[ -n "${GH_TOKEN:-}" ]] || fail 'GH_TOKEN is required for an https://github.com origin'
    auth_header="$(printf 'x-access-token:%s' "$GH_TOKEN" | base64 | tr -d '\n')"
    git_args+=(-c "http.https://github.com/.extraheader=AUTHORIZATION: basic ${auth_header}")
fi

if timeout 90s git "${git_args[@]}" push origin HEAD:main >&2; then
    output true "$published_sha" "$reason"
    if [[ -n "${AUTONOMOUS_UPDATE_RESULTS_DIR:-}" ]]; then
        mkdir -p -- "$AUTONOMOUS_UPDATE_RESULTS_DIR"
        printf '%s\n' "$published_sha" >"$AUTONOMOUS_UPDATE_RESULTS_DIR/pushed-sha"
    fi
    exit 0
fi

remote_sha=""
remote_output="$(timeout 90s git "${git_args[@]}" ls-remote origin refs/heads/main 2>/dev/null)" || {
    output false "$published_sha" push-failed
    fail 'push failed and remote HEAD could not be verified'
}
if [[ -n "$remote_output" ]]; then
    remote_sha="${remote_output%%[[:space:]]*}"
fi
[[ "$remote_sha" =~ ^[0-9a-f]{40}$ ]] || {
    output false "$published_sha" push-failed
    fail 'push failed and remote main SHA was unavailable or invalid'
}
if [[ "$remote_sha" == "$published_sha" ]]; then
    output true "$published_sha" "$reason"
    if [[ -n "${AUTONOMOUS_UPDATE_RESULTS_DIR:-}" ]]; then
        mkdir -p -- "$AUTONOMOUS_UPDATE_RESULTS_DIR"
        printf '%s\n' "$published_sha" >"$AUTONOMOUS_UPDATE_RESULTS_DIR/pushed-sha"
    fi
    exit 0
fi
if [[ "$remote_sha" != "$expected_base" ]]; then
    output false "$remote_sha" main-advanced
    exit 0
fi
output false "$published_sha" push-failed
fail 'push failed while remote main remained at the expected base'
