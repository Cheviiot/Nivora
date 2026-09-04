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
    "$fixture/repo/other"
cp "$repo_root/.github/tools/validate_update_artifact.sh" \
    "$fixture/repo/.github/tools/"
printf "name='demo'\nversion='1'\nrelease=5\nsummary='safe'\nsources=(\n 'https://example.invalid/demo'\n)\nchecksums=(\n 'sha256:%064d'\n)\n" 1 \
    >"$fixture/repo/demo/Staplerfile"
printf "name='other'\nversion='1'\nrelease=5\nsummary='safe'\nsources=(\n 'https://example.invalid/other'\n)\nchecksums=(\n 'sha256:%064d'\n)\n" 1 \
    >"$fixture/repo/other/Staplerfile"
printf '#!/bin/bash\nexit 0\n' >"$fixture/repo/.github/tools/run_checks.sh"
git -C "$fixture/repo" init -q
git -C "$fixture/repo" config user.name test
git -C "$fixture/repo" config user.email test@example.invalid
git -C "$fixture/repo" add .
git -C "$fixture/repo" commit -qm fixture

printf "name='demo'\nversion='2'\nrelease=1\nsummary='safe'\nsources=(\n 'https://example.invalid/demo'\n)\nchecksums=(\n 'sha256:%064d'\n)\n" 2 \
    >"$fixture/repo/demo/Staplerfile"
git -C "$fixture/repo" diff --binary -- demo/Staplerfile >"$fixture/good.patch"
git -C "$fixture/repo" restore -- demo/Staplerfile

printf "name='demo'\nversion='2'\nrelease=1\nsummary='pwned'\nsources=(\n 'https://example.invalid/demo'\n)\nchecksums=(\n 'sha256:%064d'\n)\n" 2 \
    >"$fixture/repo/demo/Staplerfile"
git -C "$fixture/repo" diff --binary -- demo/Staplerfile \
    >"$fixture/recipe-code.patch"
git -C "$fixture/repo" restore -- demo/Staplerfile

printf '#!/bin/bash\necho forged\nexit 0\n' \
    >"$fixture/repo/.github/tools/run_checks.sh"
git -C "$fixture/repo" diff --binary -- .github/tools/run_checks.sh \
    >"$fixture/forged.patch"
git -C "$fixture/repo" restore -- .github/tools/run_checks.sh

reset_good_fixture() {
    if [[ -d "$fixture/results" ]]; then
        find "$fixture/results" -mindepth 1 -delete
    else
        install -d "$fixture/results"
    fi
    install -d "$fixture/results/demo"
    printf 'demo\n' >"$fixture/results/successful-packages"
    : >"$fixture/results/failed-packages"
    printf 'demo\n' >"$fixture/results/checked-packages"
    printf 'success\n' >"$fixture/results/demo/result"
    printf 'verify-artifact\n' >"$fixture/results/demo/phase"
    cp "$fixture/good.patch" "$fixture/results/demo/update.patch"
}

reset_failed_fixture() {
    reset_good_fixture
    : >"$fixture/results/successful-packages"
    printf 'demo\tclean-build\n' >"$fixture/results/failed-packages"
    printf 'failure\n' >"$fixture/results/demo/result"
    printf 'clean-build\n' >"$fixture/results/demo/phase"
    printf 'package=demo\nphase=clean-build\nexit_status=1\n' \
        >"$fixture/results/demo/FAILED"
    rm "$fixture/results/demo/update.patch"
}

run_validator() {
    local expected_updates="${2:-}"
    if [[ -z "$expected_updates" ]]; then
        expected_updates='{"demo":{"current":"1","latest":"2","fingerprints":{}}}'
    fi
    AUTONOMOUS_UPDATE_RESULTS_DIR="$fixture/results" \
    DETECTED_PACKAGES_JSON="${1:-[\"demo\"]}" \
    EXPECTED_UPDATES_JSON="$expected_updates" \
        "$fixture/repo/.github/tools/validate_update_artifact.sh"
}

expect_failure() {
    local label="$1"
    shift
    if "$@" >"$fixture/failure.log" 2>&1; then
        echo "expected validator failure: ${label}" >&2
        exit 1
    fi
}

reset_good_fixture
run_validator '["demo"]' >/dev/null

reset_failed_fixture
run_validator '["demo"]' >/dev/null

reset_failed_fixture
printf 'demo\t../../publish\n' >"$fixture/results/failed-packages"
expect_failure unsafe-failure-phase run_validator '["demo"]'

reset_good_fixture
cp "$fixture/forged.patch" "$fixture/results/demo/update.patch"
expect_failure forged-patch run_validator '["demo"]'

reset_good_fixture
cp "$fixture/recipe-code.patch" "$fixture/results/demo/update.patch"
expect_failure forged-recipe-code run_validator '["demo"]'

reset_good_fixture
rm "$fixture/results/demo/update.patch"
ln -s "$fixture/good.patch" "$fixture/results/demo/update.patch"
expect_failure symlink run_validator '["demo"]'

reset_good_fixture
expect_failure missing-result run_validator '["demo","other"]'

reset_good_fixture
printf 'demo\ndemo\n' >"$fixture/results/successful-packages"
expect_failure duplicate-package run_validator '["demo"]'

reset_good_fixture
printf 'demo\nunknown\n' >"$fixture/results/successful-packages"
expect_failure unknown-package run_validator '["demo"]'

reset_good_fixture
printf 'static-checks\n' >"$fixture/results/demo/phase"
expect_failure wrong-success-phase run_validator '["demo"]'

reset_good_fixture
printf 'forged\n' >"$fixture/results/demo/unexpected-command.sh"
expect_failure unexpected-result-file run_validator '["demo"]'

reset_good_fixture
expect_failure wrong-expected-version run_validator '["demo"]' \
    '{"demo":{"current":"1","latest":"3","fingerprints":{}}'

echo 'OK: строгая проверка update artifact отклоняет подмену и неполные результаты'
