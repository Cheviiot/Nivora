#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="$(mktemp -d)"
cleanup() {
    find "$fixture" -mindepth 1 -delete
    rmdir "$fixture"
}
trap cleanup EXIT

install -d \
    "$fixture/repo/.github/tools" \
    "$fixture/repo/demo" \
    "$fixture/repo/other" \
    "$fixture/repo/parsec" \
    "$fixture/repo/chatgpt" \
    "$fixture/repo/antigravity/.stapler" \
    "$fixture/bin" \
    "$fixture/runner"
cp "$repo_root/.github/tools/autonomous_package_updates.sh" \
    "$fixture/repo/.github/tools/"
for package in demo other; do
    printf "name='%s'\nversion='1'\nrelease=4\nchecksum='old'\n" "$package" \
        >"$fixture/repo/$package/Staplerfile"
done
fingerprint_a="$(printf 'a%.0s' {1..64})"
fingerprint_b="$(printf 'b%.0s' {1..64})"
fingerprint_c="$(printf 'c%.0s' {1..64})"
printf "name='parsec'\nversion='1'\nrelease=4\nsource_fingerprint='%s'\nchecksum='old'\n" \
    "$fingerprint_a" >"$fixture/repo/parsec/Staplerfile"
printf "name='chatgpt'\nversion='1'\nrelease=4\nsource_fingerprint_amd64='%s'\nsource_fingerprint_arm64='%s'\nchecksum='old'\n" \
    "$fingerprint_a" "$fingerprint_a" >"$fixture/repo/chatgpt/Staplerfile"
printf "name='antigravity'\nversion='1.0.0'\nrelease=4\nupstream_hub='1.0.0-600'\nchecksum='old'\n" \
    >"$fixture/repo/antigravity/Staplerfile"
cat >"$fixture/repo/antigravity/.stapler/update-run" <<'EOF'
#!/bin/bash
set -euo pipefail
[[ "$ANTIGRAVITY_EXPECTED_FINGERPRINT" == "$MUTABLE_TEST_FINGERPRINT" ]]
release=1
[[ "$1" != 1.0.0 ]] || release=5
hub="$1-${ANTIGRAVITY_TEST_BUILD:-700}"
sed -i -e "s/^version='1.0.0'$/version='$1'/" \
    -e "s/^release=4$/release=$release/" \
    -e "s/^upstream_hub='1.0.0-600'$/upstream_hub='$hub'/" \
    -e "s/^checksum='old'$/checksum='new'/" antigravity/Staplerfile
EOF
chmod 0755 "$fixture/repo/antigravity/.stapler/update-run"
# The variable is intentionally expanded later by the generated mock.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/bash' \
    'if [[ "$2" == chatgpt ]]; then' \
    '  printf "%s\t%s\n" source_fingerprint_amd64 "${MUTABLE_TEST_FINGERPRINT:?}" source_fingerprint_arm64 "$MUTABLE_TEST_FINGERPRINT"' \
    'else' \
    '  printf "source_fingerprint\t%s\n" "${MUTABLE_TEST_FINGERPRINT:?}"' \
    'fi' \
    >"$fixture/repo/.github/tools/package_updates.sh"
chmod 0755 "$fixture/repo/.github/tools/package_updates.sh"
for tool in sync_readme_versions.py run_checks.sh verify_artifacts.sh; do
    printf '#!/bin/bash\nprintf %s\\n >>"%s"\n' \
        "$tool" "$fixture/later-phases" >"$fixture/repo/.github/tools/$tool"
    chmod 0755 "$fixture/repo/.github/tools/$tool"
done
cat >"$fixture/repo/.github/tools/clean_build.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
printf '%s\t%s\n' "$NIVORA_ALT_BRANCH" "$1" >>"$BUILD_TEST_LOG"
EOF
chmod 0755 "$fixture/repo/.github/tools/clean_build.sh"
export BUILD_TEST_LOG="$fixture/build.log"
cat >"$fixture/repo/.github/tools/test_package_lifecycle.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
printf '%s\t%s\n' "$NIVORA_ALT_BRANCH" "$NIVORA_LIFECYCLE_PACKAGES" >>"$LIFECYCLE_TEST_LOG"
exit "${LIFECYCLE_TEST_EXIT:-0}"
EOF
chmod 0755 "$fixture/repo/.github/tools/test_package_lifecycle.sh"
export LIFECYCLE_TEST_LOG="$fixture/lifecycle.log"
# The source gate runs before anything touches the recipe. It is stubbed as a
# switch so the test can drive both outcomes.
cat >"$fixture/repo/.github/tools/check_source_availability.sh" <<EOF
#!/bin/bash
printf 'check-sources %s %s\n' "\$1" "\$2" >>'$fixture/source-gate'
exit "\${SOURCE_GATE_EXIT:-0}"
EOF
chmod 0755 "$fixture/repo/.github/tools/check_source_availability.sh"
cat >"$fixture/bin/stplr-spec" <<EOF
#!/bin/bash
printf 'stplr-spec failed\n' >>'$fixture/first-phase'
exit 42
EOF
chmod 0755 "$fixture/bin/stplr-spec"
git -C "$fixture/repo" init -q
git -C "$fixture/repo" config user.name test
git -C "$fixture/repo" config user.email test@example.invalid
git -C "$fixture/repo" add .
git -C "$fixture/repo" commit -qm fixture

PATH="$fixture/bin:$PATH" \
STPLR_SPEC_COMMAND="$fixture/bin/stplr-spec" \
RUNNER_TEMP="$fixture/runner" \
AUTONOMOUS_UPDATE_RESULTS_DIR="$fixture/results" \
UPDATE_PLAN_JSON='{"demo":{"current":"1","latest":"2","fingerprints":{}}}' \
    "$fixture/repo/.github/tools/autonomous_package_updates.sh" demo

test -f "$fixture/first-phase" || {
    find "$fixture/results" -type f -maxdepth 3 -print -exec sed -n '1,40p' {} \;
    exit 1
}
test ! -e "$fixture/later-phases"
grep -Fxq 'phase=update-recipe' "$fixture/results/demo/FAILED"
grep -Fxq $'demo\tupdate-recipe' "$fixture/results/failed-packages"

cat >"$fixture/bin/stplr-spec" <<'EOF'
#!/bin/bash
case "$1" in
get-field)
    if [[ "${!#}" == upstream_hub ]]; then
        sed -n "s/^upstream_hub='\([^']*\)'$/\1/p" "$3"
    elif [[ "${!#}" == version ]]; then
        sed -n "s/^version='\([^']*\)'$/\1/p" "$3"
    else
        printf '4\n'
    fi
    ;;
update-checksums)
    recipe=''
    while [[ "$#" -gt 0 ]]; do
        if [[ "$1" == --path ]]; then
            recipe="$2"
            break
        fi
        shift
    done
    sed -i "s/^checksum='old'$/checksum='new'/" "$recipe"
    ;;
update-package)
    updated_version=2
    if [[ "$2" == demo ]]; then
        updated_version="${DEMO_UPDATED_VERSION:-2}"
    fi
    sed -i -e "s/^version='1'$/version='$updated_version'/" -e 's/^release=4$/release=1/' \
        -e "s/^checksum='old'$/checksum='new'/" "$2/Staplerfile"
    ;;
*)
    exit 2
    ;;
esac
EOF
chmod 0755 "$fixture/bin/stplr-spec"

for latest in 1.0.0 2.0.0; do
    fingerprint="$(printf '%s' "$latest-700" | sha256sum | awk '{print $1}')"
    PATH="$fixture/bin:$PATH" \
    STPLR_SPEC_COMMAND="$fixture/bin/stplr-spec" \
    RUNNER_TEMP="$fixture/runner" \
    AUTONOMOUS_UPDATE_RESULTS_DIR="$fixture/antigravity-results-$latest" \
    MUTABLE_TEST_FINGERPRINT="$fingerprint" \
    UPDATE_PLAN_JSON="{\"antigravity\":{\"current\":\"1.0.0\",\"latest\":\"$latest\",\"fingerprints\":{\"source_fingerprint\":\"$fingerprint\"}}}" \
        "$fixture/repo/.github/tools/autonomous_package_updates.sh" antigravity
    grep -Fxq antigravity "$fixture/antigravity-results-$latest/successful-packages"
    grep -Fq "+upstream_hub='$latest-700'" \
        "$fixture/antigravity-results-$latest/antigravity/update.patch"
done

PATH="$fixture/bin:$PATH" \
STPLR_SPEC_COMMAND="$fixture/bin/stplr-spec" \
RUNNER_TEMP="$fixture/runner" \
AUTONOMOUS_UPDATE_RESULTS_DIR="$fixture/antigravity-unplanned" \
MUTABLE_TEST_FINGERPRINT="$fingerprint" \
ANTIGRAVITY_TEST_BUILD=701 \
UPDATE_PLAN_JSON="{\"antigravity\":{\"current\":\"1.0.0\",\"latest\":\"2.0.0\",\"fingerprints\":{\"source_fingerprint\":\"$fingerprint\"}}}" \
    "$fixture/repo/.github/tools/autonomous_package_updates.sh" antigravity
grep -Fxq $'antigravity\tpin-source-fingerprint' \
    "$fixture/antigravity-unplanned/failed-packages"
test ! -e "$fixture/antigravity-unplanned/antigravity/update.patch"

PATH="$fixture/bin:$PATH" \
STPLR_SPEC_COMMAND="$fixture/bin/stplr-spec" \
RUNNER_TEMP="$fixture/runner" \
AUTONOMOUS_UPDATE_RESULTS_DIR="$fixture/mutable-results" \
MUTABLE_TEST_FINGERPRINT="$fingerprint_b" \
UPDATE_PLAN_JSON="{\"parsec\":{\"current\":\"1\",\"latest\":\"1\",\"fingerprints\":{\"source_fingerprint\":\"${fingerprint_b}\"}}}" \
    "$fixture/repo/.github/tools/autonomous_package_updates.sh" parsec

grep -Fxq parsec "$fixture/mutable-results/successful-packages"
grep -Fq '+release=5' "$fixture/mutable-results/parsec/update.patch"
grep -Fq "+source_fingerprint='${fingerprint_b}'" \
    "$fixture/mutable-results/parsec/update.patch"
grep -Fq "+checksum='new'" "$fixture/mutable-results/parsec/update.patch"

PATH="$fixture/bin:$PATH" \
STPLR_SPEC_COMMAND="$fixture/bin/stplr-spec" \
RUNNER_TEMP="$fixture/runner" \
AUTONOMOUS_UPDATE_RESULTS_DIR="$fixture/raced-results" \
MUTABLE_TEST_FINGERPRINT="$fingerprint_c" \
UPDATE_PLAN_JSON="{\"parsec\":{\"current\":\"1\",\"latest\":\"1\",\"fingerprints\":{\"source_fingerprint\":\"${fingerprint_b}\"}}}" \
    "$fixture/repo/.github/tools/autonomous_package_updates.sh" parsec
grep -Fxq $'parsec\tupdate-recipe' "$fixture/raced-results/failed-packages"
test ! -s "$fixture/raced-results/parsec/failed.patch"

for latest in 1 2; do
    expected_release=1
    [[ "$latest" != 1 ]] || expected_release=5
    PATH="$fixture/bin:$PATH" \
    STPLR_SPEC_COMMAND="$fixture/bin/stplr-spec" \
    RUNNER_TEMP="$fixture/runner" \
    AUTONOMOUS_UPDATE_RESULTS_DIR="$fixture/chatgpt-results-$latest" \
    MUTABLE_TEST_FINGERPRINT="$fingerprint_b" \
    UPDATE_PLAN_JSON="{\"chatgpt\":{\"current\":\"1\",\"latest\":\"$latest\",\"fingerprints\":{\"source_fingerprint_amd64\":\"${fingerprint_b}\",\"source_fingerprint_arm64\":\"${fingerprint_b}\"}}}" \
        "$fixture/repo/.github/tools/autonomous_package_updates.sh" chatgpt
    grep -Fxq chatgpt "$fixture/chatgpt-results-$latest/successful-packages"
    grep -Fq "+release=$expected_release" "$fixture/chatgpt-results-$latest/chatgpt/update.patch"
    grep -Fq "+source_fingerprint_amd64='${fingerprint_b}'" \
        "$fixture/chatgpt-results-$latest/chatgpt/update.patch"
done

PATH="$fixture/bin:$PATH" \
STPLR_SPEC_COMMAND="$fixture/bin/stplr-spec" \
RUNNER_TEMP="$fixture/runner" \
AUTONOMOUS_UPDATE_RESULTS_DIR="$fixture/chatgpt-raced-results" \
MUTABLE_TEST_FINGERPRINT="$fingerprint_c" \
UPDATE_PLAN_JSON="{\"chatgpt\":{\"current\":\"1\",\"latest\":\"2\",\"fingerprints\":{\"source_fingerprint_amd64\":\"${fingerprint_b}\",\"source_fingerprint_arm64\":\"${fingerprint_b}\"}}}" \
    "$fixture/repo/.github/tools/autonomous_package_updates.sh" chatgpt
grep -Fxq $'chatgpt\tupdate-recipe' "$fixture/chatgpt-raced-results/failed-packages"
test ! -s "$fixture/chatgpt-raced-results/chatgpt/failed.patch"
# Each successful candidate runs one build and one lifecycle gate, both on
# p11. Failed source/fingerprint checks must not reach either gate.
expected_gates=$'p11\tantigravity\np11\tantigravity\np11\tparsec\np11\tchatgpt\np11\tchatgpt'
[[ "$(cat "$BUILD_TEST_LOG")" == "$expected_gates" ]]
[[ "$(cat "$LIFECYCLE_TEST_LOG")" == "$expected_gates" ]]

LIFECYCLE_TEST_EXIT=47 \
PATH="$fixture/bin:$PATH" \
STPLR_SPEC_COMMAND="$fixture/bin/stplr-spec" \
RUNNER_TEMP="$fixture/runner" \
AUTONOMOUS_UPDATE_RESULTS_DIR="$fixture/lifecycle-failed-results" \
MUTABLE_TEST_FINGERPRINT="$fingerprint_b" \
UPDATE_PLAN_JSON="{\"parsec\":{\"current\":\"1\",\"latest\":\"1\",\"fingerprints\":{\"source_fingerprint\":\"${fingerprint_b}\"}}}" \
    "$fixture/repo/.github/tools/autonomous_package_updates.sh" parsec
grep -Fxq $'parsec\ttest-lifecycle' "$fixture/lifecycle-failed-results/failed-packages"
test ! -e "$fixture/lifecycle-failed-results/parsec/update.patch"

SOURCE_GATE_EXIT=1 \
PATH="$fixture/bin:$PATH" \
STPLR_SPEC_COMMAND="$fixture/bin/stplr-spec" \
RUNNER_TEMP="$fixture/runner" \
AUTONOMOUS_UPDATE_RESULTS_DIR="$fixture/unpublished-results" \
UPDATE_PLAN_JSON='{"demo":{"current":"1","latest":"2","fingerprints":{}}}' \
    "$fixture/repo/.github/tools/autonomous_package_updates.sh" demo

grep -Fxq 'phase=check-sources' "$fixture/unpublished-results/demo/FAILED"
grep -Fxq $'demo\tcheck-sources' "$fixture/unpublished-results/failed-packages"
test ! -s "$fixture/unpublished-results/demo/failed.patch"
grep -Fxq 'check-sources demo 2' "$fixture/source-gate"

# A second upstream release can appear between detection and update-package.
# Reject that candidate before any expensive gate, while a separate candidate
# from the same batch still reaches publication with its planned version.
: >"$BUILD_TEST_LOG"
: >"$LIFECYCLE_TEST_LOG"
DEMO_UPDATED_VERSION=3 \
PATH="$fixture/bin:$PATH" \
STPLR_SPEC_COMMAND="$fixture/bin/stplr-spec" \
RUNNER_TEMP="$fixture/runner" \
AUTONOMOUS_UPDATE_RESULTS_DIR="$fixture/version-race-results" \
UPDATE_PLAN_JSON='{"demo":{"current":"1","latest":"2","fingerprints":{}},"other":{"current":"1","latest":"2","fingerprints":{}}}' \
    "$fixture/repo/.github/tools/autonomous_package_updates.sh" demo other

[[ "$(cat "$fixture/version-race-results/successful-packages")" == other ]]
[[ "$(cat "$fixture/version-race-results/failed-packages")" == $'demo\tupdate-recipe' ]]
grep -Fxq 'phase=update-recipe' "$fixture/version-race-results/demo/FAILED"
grep -Fq 'demo planned version 2, but updater wrote 3' \
    "$fixture/version-race-results/demo/update.log"
test ! -e "$fixture/version-race-results/demo/update.patch"
grep -Fq "+version='2'" "$fixture/version-race-results/other/update.patch"
[[ "$(cat "$BUILD_TEST_LOG")" == $'p11\tother' ]]
[[ "$(cat "$LIFECYCLE_TEST_LOG")" == $'p11\tother' ]]

echo 'OK: updater isolates version races, mutable-source races and unpublished sources'
