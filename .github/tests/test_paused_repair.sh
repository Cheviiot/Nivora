#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="$(mktemp -d)"
cleanup() {
    find "$fixture" -mindepth 1 -delete
    rmdir "$fixture"
}
trap cleanup EXIT

mkdir -p "$fixture/repo/.github/tools" "$fixture/results"
cp "$repo_root/.github/tools/validate_paused_repair.sh" \
    "$repo_root/.github/tools/validate_update_artifact.sh" "$fixture/repo/.github/tools/"
for package in alpha beta unchanged; do
    mkdir -p "$fixture/repo/$package"
    printf "name='%s'\nversion='1'\nrelease=5\nsummary='safe'\nsources=(\n 'https://example.invalid/%s'\n)\nchecksums=(\n 'sha256:%064d'\n)\n" \
        "$package" "$package" 1 >"$fixture/repo/$package/Staplerfile"
done
printf '# Catalogue\n' >"$fixture/repo/README.md"
cat >"$fixture/repo/.github/tools/sync_readme_versions.py" <<'EOF'
#!/bin/bash
set -euo pipefail
printf '# Catalogue: alpha2 beta2 unchanged1\n' >README.md
EOF
cat >"$fixture/repo/.github/tools/run_checks.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
grep -Fxq "version='2'" alpha/Staplerfile
grep -Fxq "version='2'" beta/Staplerfile
grep -Fxq "version='1'" unchanged/Staplerfile
printf 'static\n' >>"$REPAIR_GATE_LOG"
EOF
for tool in clean_build.sh verify_artifacts.sh test_package_lifecycle.sh; do
    cat >"$fixture/repo/.github/tools/$tool" <<'EOF'
#!/bin/bash
set -euo pipefail
[[ "$NIVORA_ALT_BRANCH" == p11 && "$NIVORA_STPLR_CHANNEL" == stable ]]
tool="${0##*/}"
if [[ "$tool" == test_package_lifecycle.sh ]]; then
    [[ "$#" -eq 0 && -z "${NIVORA_LIFECYCLE_PACKAGES:-}" ]]
else
    [[ "$#" -eq 1 && "$1" == --all ]]
fi
for recipe in */Staplerfile; do
    package="${recipe%/Staplerfile}"
    printf '%s %s\n' "$tool" "$package" >>"$REPAIR_GATE_LOG"
    if [[ "$tool" == clean_build.sh && "$package" == unchanged && "${REPAIR_FAIL_UNCHANGED:-0}" == 1 ]]; then
        exit 42
    fi
done
if [[ "$tool" == test_package_lifecycle.sh && "${REPAIR_MUTATE_TREE:-0}" == 1 ]]; then
    printf 'changed after gates\n' >>README.md
elif [[ "$tool" == test_package_lifecycle.sh && "${REPAIR_MUTATE_TREE:-0}" == outside ]]; then
    printf '\n# changed after gates\n' >>.github/tools/run_checks.sh
fi
EOF
done
chmod 0755 "$fixture/repo/.github/tools/"*
git -C "$fixture/repo" init -q
git -C "$fixture/repo" config user.name test
git -C "$fixture/repo" config user.email test@example.invalid
git -C "$fixture/repo" add .
git -C "$fixture/repo" commit -qm fixture
base="$(git -C "$fixture/repo" rev-parse HEAD)"

printf 'alpha\nbeta\n' >"$fixture/results/successful-packages"
cp "$fixture/results/successful-packages" "$fixture/results/checked-packages"
: >"$fixture/results/failed-packages"
for package in alpha beta; do
    mkdir -p "$fixture/results/$package"
    sed -i -e "s/^version='1'$/version='2'/" -e 's/^release=5$/release=1/' \
        -e "s/$(printf '%064d' 1)/$(printf '%064d' 2)/" "$fixture/repo/$package/Staplerfile"
    git -C "$fixture/repo" diff -- "$package/Staplerfile" >"$fixture/results/$package/update.patch"
    printf 'success\n' >"$fixture/results/$package/result"
    printf 'test-lifecycle\n' >"$fixture/results/$package/phase"
    git -C "$fixture/repo" restore -- "$package/Staplerfile"
done

export REPAIR_GATE_LOG="$fixture/gates"
export AUTONOMOUS_UPDATE_RESULTS_DIR="$fixture/results"
export DETECTED_PACKAGES_JSON='["alpha","beta"]'
export EXPECTED_UPDATES_JSON='{"alpha":{"current":"1","latest":"2","fingerprints":{}},"beta":{"current":"1","latest":"2","fingerprints":{}}}'
export GITHUB_OUTPUT="$fixture/output"

run_repair() {
    EXPECTED_BASE_SHA="${1:-$base}" \
        NIVORA_ALT_BRANCH=sisyphus NIVORA_STPLR_CHANNEL=main NIVORA_LIFECYCLE_PACKAGES=alpha \
        "$fixture/repo/.github/tools/validate_paused_repair.sh"
}

reset_case() {
    git -C "$fixture/repo" restore --source=HEAD --staged --worktree .
    : >"$REPAIR_GATE_LOG"
    : >"$GITHUB_OUTPUT"
}

# The entire successful batch and untouched catalogue members reach every
# gate. An ambient narrow lifecycle selection must not weaken the full check.
reset_case
run_repair >/dev/null
expected=$'static\nclean_build.sh alpha\nclean_build.sh beta\nclean_build.sh unchanged\nverify_artifacts.sh alpha\nverify_artifacts.sh beta\nverify_artifacts.sh unchanged\ntest_package_lifecycle.sh alpha\ntest_package_lifecycle.sh beta\ntest_package_lifecycle.sh unchanged'
[[ "$(cat "$REPAIR_GATE_LOG")" == "$expected" ]]
grep -Fxq "tree=$(git -C "$fixture/repo" write-tree)" "$GITHUB_OUTPUT"

# Exact base mismatches and a forged second patch fail before any patch is
# applied, even when the first patch is a valid independently checked update.
reset_case
if run_repair aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa >"$fixture/failure.log" 2>&1; then
    echo 'repair accepted the wrong detection base' >&2
    exit 1
fi
[[ ! -s "$REPAIR_GATE_LOG" && ! -s "$GITHUB_OUTPUT" ]]
cp "$fixture/results/beta/update.patch" "$fixture/beta.patch"
sed -i "s/^ summary='safe'$/-summary='safe'\n+summary='forged'/" "$fixture/results/beta/update.patch"
if run_repair >"$fixture/failure.log" 2>&1; then
    echo 'repair applied a semantically forbidden batch' >&2
    exit 1
fi
git -C "$fixture/repo" diff --quiet
[[ ! -s "$REPAIR_GATE_LOG" && ! -s "$GITHUB_OUTPUT" ]]
cp "$fixture/beta.patch" "$fixture/results/beta/update.patch"

# A failure in an unchanged package must prevent a successful repair proof.
reset_case
if REPAIR_FAIL_UNCHANGED=1 run_repair >"$fixture/failure.log" 2>&1; then
    echo 'repair ignored a failure outside the updated packages' >&2
    exit 1
fi
grep -Fxq 'clean_build.sh unchanged' "$REPAIR_GATE_LOG"
[[ ! -s "$GITHUB_OUTPUT" ]]
if grep -q '^verify_artifacts.sh' "$REPAIR_GATE_LOG"; then
    echo 'repair continued after a failed full build' >&2
    exit 1
fi

# A gate may not silently change the tree it claims to have verified.
for mutation in 1 outside; do
    reset_case
    if REPAIR_MUTATE_TREE="$mutation" run_repair >"$fixture/failure.log" 2>&1; then
        echo 'repair accepted a tree changed by the gates' >&2
        exit 1
    fi
    [[ ! -s "$GITHUB_OUTPUT" ]]
done

echo 'OK: paused repair binds exact base and combined batch to every stable p11 gate'
