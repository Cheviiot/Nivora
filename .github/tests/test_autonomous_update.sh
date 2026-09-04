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
    "$fixture/repo/parsec" \
    "$fixture/bin" \
    "$fixture/runner"
cp "$repo_root/.github/tools/autonomous_package_updates.sh" \
    "$fixture/repo/.github/tools/"
printf 'name=demo\n' >"$fixture/repo/demo/Staplerfile"
fingerprint_a="$(printf 'a%.0s' {1..64})"
fingerprint_b="$(printf 'b%.0s' {1..64})"
fingerprint_c="$(printf 'c%.0s' {1..64})"
printf "name='parsec'\nversion='1'\nrelease=4\nsource_fingerprint='%s'\nchecksum='old'\n" \
    "$fingerprint_a" >"$fixture/repo/parsec/Staplerfile"
# The variable is intentionally expanded later by the generated mock.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/bash' \
    'printf "source_fingerprint\t%s\n" "${MUTABLE_TEST_FINGERPRINT:?}"' \
    >"$fixture/repo/.github/tools/package_updates.sh"
chmod 0755 "$fixture/repo/.github/tools/package_updates.sh"
for tool in sync_readme_versions.py run_checks.sh clean_build.sh verify_artifacts.sh; do
    printf '#!/bin/bash\nprintf %s\\n >>"%s"\n' \
        "$tool" "$fixture/later-phases" >"$fixture/repo/.github/tools/$tool"
    chmod 0755 "$fixture/repo/.github/tools/$tool"
done
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
    printf '4\n'
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
*)
    exit 2
    ;;
esac
EOF
chmod 0755 "$fixture/bin/stplr-spec"

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

echo 'OK: updater fail-fast и отклоняет mutable-source race'
