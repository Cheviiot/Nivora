#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/nivora-maintenance-env.XXXXXX")"
cleanup() {
    find "$scratch" -mindepth 1 -delete
    rmdir "$scratch"
}
trap cleanup EXIT

# run_checks.sh also runs inside candidate updates with real diagnostics in the
# environment. Exercise fixture publishers under that same ambient contract.
mkdir "$scratch/live-results" "$scratch/expected-results"
printf 'live publication marker\n' >"$scratch/expected-results/pushed-sha"
printf 'live package result\n' >"$scratch/expected-results/successful-packages"
cp "$scratch/expected-results/"* "$scratch/live-results/"

for test_script in test_publish_update_commit.sh test_updater_pause_preflight.sh; do
    if ! AUTONOMOUS_UPDATE_RESULTS_DIR="$scratch/live-results" BASH_ENV=/dev/null \
        bash "$repo_root/.github/tests/$test_script" >"$scratch/$test_script.log" 2>&1; then
        cat "$scratch/$test_script.log" >&2
        echo "maintenance environment regression: ${test_script} failed" >&2
        exit 1
    fi
    if ! diff -ru "$scratch/expected-results" "$scratch/live-results"; then
        echo "maintenance environment regression: ${test_script} changed live diagnostics" >&2
        exit 1
    fi
done

echo 'OK: maintenance fixtures leave live updater diagnostics untouched'
