#!/bin/bash
# Verify the entire candidate tree before publishing a repair while paused.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
cd "$repo_root"

expected_base="${EXPECTED_BASE_SHA:?EXPECTED_BASE_SHA is required}"
results_dir="${AUTONOMOUS_UPDATE_RESULTS_DIR:?AUTONOMOUS_UPDATE_RESULTS_DIR is required}"
[[ "$expected_base" =~ ^[0-9a-f]{40}$ ]]
[[ "$(git rev-parse HEAD)" == "$expected_base" ]]
git diff --quiet
git diff --cached --quiet

# Validate before applying any artifact bytes, using trusted scripts at the
# exact detection base. The privileged publisher repeats this validation.
"$script_dir/validate_update_artifact.sh"
[[ -s "$results_dir/successful-packages" ]]
while IFS= read -r package; do
    [[ -n "$package" ]] || continue
    git apply "$results_dir/$package/update.patch"
done <"$results_dir/successful-packages"
"$script_dir/sync_readme_versions.py"
"$script_dir/run_checks.sh"

git add -- README.md */Staplerfile
git diff --quiet
verified_tree="$(git write-tree)"
export NIVORA_STPLR_CHANNEL=stable NIVORA_ALT_BRANCH=p11
unset NIVORA_LIFECYCLE_PACKAGES
"$script_dir/clean_build.sh" --all
"$script_dir/verify_artifacts.sh" --all
"$script_dir/test_package_lifecycle.sh"

# Builds must not change the recipes checked by the full gate. Bind its result
# to a Git tree so the publisher cannot accidentally publish a different batch.
git add -- README.md */Staplerfile
git diff --quiet
[[ "$(git write-tree)" == "$verified_tree" ]]
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf 'tree=%s\n' "$verified_tree" >>"$GITHUB_OUTPUT"
fi
printf 'Verified full ALT p11 repair tree %s\n' "$verified_tree"
