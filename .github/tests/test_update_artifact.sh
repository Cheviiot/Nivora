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
    printf 'test-lifecycle\n' >"$fixture/results/demo/phase"
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
    '{"demo":{"current":"1","latest":"3","fingerprints":{}}}'

# AniDesk's Debian filename version is derived from the approved tag version.
# Its update hook writes this scalar unquoted; arbitrary values stay forbidden.
install -d "$fixture/repo/anidesk"
cat >"$fixture/repo/anidesk/Staplerfile" <<'EOF'
name='anidesk'
version='0.0.1-beta.7'
debian_version='0.0.1.beta.7'
release=5
sources=(
 'https://example.invalid/v${version}/anidesk_${debian_version}_amd64.deb'
)
checksums=(
 'sha256:0000000000000000000000000000000000000000000000000000000000000001'
)
EOF
git -C "$fixture/repo" add anidesk/Staplerfile
git -C "$fixture/repo" commit -qm 'fixture anidesk'
for latest in 0.0.1-beta.8 0.0.2; do
    sed -i \
        -e "s/^version='0.0.1-beta.7'$/version='$latest'/" \
        -e "s/^debian_version='0.0.1.beta.7'$/debian_version=${latest/-beta./.beta.}/" \
        -e 's/^release=5$/release=1/' \
        -e "s/$(printf '%064d' 1)/$(printf '%064d' 2)/" \
        "$fixture/repo/anidesk/Staplerfile"
    reset_good_fixture
    mv "$fixture/results/demo" "$fixture/results/anidesk"
    printf 'anidesk\n' >"$fixture/results/checked-packages"
    printf 'anidesk\n' >"$fixture/results/successful-packages"
    git -C "$fixture/repo" diff --binary -- anidesk/Staplerfile \
        >"$fixture/results/anidesk/update.patch"
    git -C "$fixture/repo" restore -- anidesk/Staplerfile
    expected="$(jq -cn --arg latest "$latest" \
        '{anidesk:{current:"0.0.1-beta.7",latest:$latest,fingerprints:{}}}')"
    run_validator '["anidesk"]' "$expected" >/dev/null
    for invalid in 0.0.1.beta.7 9.9.9; do
        sed -i "s/^+debian_version=.*$/+debian_version='$invalid'/" \
            "$fixture/results/anidesk/update.patch"
        expect_failure unplanned-anidesk-filename run_validator '["anidesk"]' "$expected"
    done
done

# Antigravity tracks a full immutable build ID through the same fingerprint
# plan, deriving the digest from upstream_hub instead of storing it twice.
install -d "$fixture/repo/antigravity"
cat >"$fixture/repo/antigravity/Staplerfile" <<'EOF'
name='antigravity'
version='2.32.1'
release=5
upstream_hub='2.32.1-600'
sources=(
 'https://storage.googleapis.com/antigravity-public/antigravity-hub/${upstream_hub}/linux-x64/Antigravity.tar.gz'
)
checksums=(
 'sha256:0000000000000000000000000000000000000000000000000000000000000001'
)
EOF
git -C "$fixture/repo" add antigravity/Staplerfile
git -C "$fixture/repo" commit -qm 'fixture antigravity'
for latest in 2.32.1 2.33.0; do
    release=1
    [[ "$latest" != 2.32.1 ]] || release=6
    hub="${latest}-700"
    fingerprint="$(printf '%s' "$hub" | sha256sum | awk '{print $1}')"
    sed -i -e "s/^version='2.32.1'$/version='$latest'/" \
        -e "s/^upstream_hub='2.32.1-600'$/upstream_hub='$hub'/" \
        -e "s/^release=5$/release=$release/" \
        -e "s/$(printf '%064d' 1)/$(printf '%064d' 2)/" \
        "$fixture/repo/antigravity/Staplerfile"
    reset_good_fixture
    mv "$fixture/results/demo" "$fixture/results/antigravity"
    printf 'antigravity\n' >"$fixture/results/checked-packages"
    printf 'antigravity\n' >"$fixture/results/successful-packages"
    git -C "$fixture/repo" diff --binary -- antigravity/Staplerfile \
        >"$fixture/results/antigravity/update.patch"
    git -C "$fixture/repo" restore -- antigravity/Staplerfile
    expected="$(jq -cn --arg latest "$latest" --arg hash "$fingerprint" \
        '{antigravity:{current:"2.32.1",latest:$latest,fingerprints:{source_fingerprint:$hash}}}')"
    run_validator '["antigravity"]' "$expected" >/dev/null
    unexpected="$(jq -c '.antigravity.fingerprints.source_fingerprint = ("a" * 64)' <<<"$expected")"
    expect_failure unplanned-antigravity-build run_validator '["antigravity"]' "$unexpected"
    unexpected="$(jq -c '.antigravity.fingerprints = {}' <<<"$expected")"
    expect_failure missing-antigravity-snapshot run_validator '["antigravity"]' "$unexpected"

    # A syntactically valid hub with another App version must be rejected even
    # if its fingerprint was supplied: the requested version is part of the pin.
    wrong_hub=9.9.9-700
    sed -i "s/+upstream_hub='$hub'/+upstream_hub='$wrong_hub'/" \
        "$fixture/results/antigravity/update.patch"
    fingerprint="$(printf '%s' "$wrong_hub" | sha256sum | awk '{print $1}')"
    unexpected="$(jq -c --arg hash "$fingerprint" \
        '.antigravity.fingerprints.source_fingerprint = $hash' <<<"$expected")"
    expect_failure wrong-antigravity-version run_validator '["antigravity"]' "$unexpected"
done

# Exercise every mutable-source package through both trust boundaries: plan
# parsing and the semantic recipe diff. A newly added fingerprint must work
# for upgrades and same-version refreshes without accepting unplanned hashes.
fingerprint_a="$(printf 'a%.0s' {1..64})"
fingerprint_b="$(printf 'b%.0s' {1..64})"
for package in chatgpt parsec; do
    case "$package" in
    chatgpt) fields=(source_fingerprint_amd64 source_fingerprint_arm64) ;;
    parsec) fields=(source_fingerprint) ;;
    esac
    install -d "$fixture/repo/$package"
    {
        printf "name='%s'\nversion='1'\nrelease=5\n" "$package"
        for field in "${fields[@]}"; do
            printf "%s='%s'\n" "$field" "$fingerprint_a"
        done
        printf "sources=(\n 'https://example.invalid/payload'\n)\nchecksums=(\n 'sha256:%064d'\n)\n" 1
    } >"$fixture/repo/$package/Staplerfile"
    git -C "$fixture/repo" add "$package/Staplerfile"
    git -C "$fixture/repo" commit -qm "fixture $package"

    fingerprints="$(printf '%s\n' "${fields[@]}" |
        jq -Rsc --arg hash "$fingerprint_b" \
            'split("\n") | map(select(length > 0) | {key: ., value: $hash}) | from_entries')"
    for latest in 2 1; do
        release=1
        [[ "$latest" != 1 ]] || release=6
        sed -i \
            -e "s/^version='1'$/version='$latest'/" \
            -e "s/^release=5$/release=$release/" \
            -e "s/$fingerprint_a/$fingerprint_b/g" \
            -e "s/$(printf '%064d' 1)/$(printf '%064d' 2)/" \
            "$fixture/repo/$package/Staplerfile"
        reset_good_fixture
        mv "$fixture/results/demo" "$fixture/results/$package"
        printf '%s\n' "$package" >"$fixture/results/checked-packages"
        printf '%s\n' "$package" >"$fixture/results/successful-packages"
        git -C "$fixture/repo" diff --binary -- "$package/Staplerfile" \
            >"$fixture/results/$package/update.patch"
        git -C "$fixture/repo" restore -- "$package/Staplerfile"
        detected="$(jq -cn --arg package "$package" '[$package]')"
        expected="$(jq -cn --arg package "$package" --arg latest "$latest" \
            --argjson fingerprints "$fingerprints" \
            '{($package): {current: "1", latest: $latest, fingerprints: $fingerprints}}')"
        run_validator "$detected" "$expected" >/dev/null

        tampered="$(jq '.[] .fingerprints |= with_entries(.value = ("c" * 64))' <<<"$expected")"
        expect_failure unplanned-fingerprint run_validator "$detected" "$tampered"
        missing="$(jq '.[] .fingerprints = {}' <<<"$expected")"
        expect_failure missing-fingerprint run_validator "$detected" "$missing"
        extra="$(jq '.[] .fingerprints.source_fingerprint_unknown = ("d" * 64)' <<<"$expected")"
        expect_failure unknown-fingerprint run_validator "$detected" "$extra"
    done
done

# The plugin snapshot digest binds the exact source commit as well as version.
package=gnome-software-plugin-stplr
commit_a="$(printf 'a%.0s' {1..40})"
commit_b="$(printf 'b%.0s' {1..40})"
fingerprint_a="$(printf '%s' "$commit_a" | sha256sum | awk '{print $1}')"
fingerprint_b="$(printf '%s' "$commit_b" | sha256sum | awk '{print $1}')"
install -d "$fixture/repo/$package"
cat >"$fixture/repo/$package/Staplerfile" <<EOF
name='$package'
version='0.3.0.git20260525192209'
release=5
upstream_commit='$commit_a'
source_fingerprint='$fingerprint_a'
sources=(
 'https://example.invalid/archive/\${upstream_commit}.tar.gz'
)
checksums=(
 'sha256:$(printf '%064d' 1)'
)
EOF
git -C "$fixture/repo" add "$package/Staplerfile"
git -C "$fixture/repo" commit -qm 'fixture plugin'
for latest in 0.3.0.git20260525192209 0.3.0.git20260526192209; do
    release=1
    [[ "$latest" != 0.3.0.git20260525192209 ]] || release=6
    sed -i -e "s/^version='0.3.0.git20260525192209'$/version='$latest'/" \
        -e "s/^release=5$/release=$release/" \
        -e "s/$commit_a/$commit_b/" \
        -e "s/$fingerprint_a/$fingerprint_b/" \
        -e "s/$(printf '%064d' 1)/$(printf '%064d' 2)/" \
        "$fixture/repo/$package/Staplerfile"
    reset_good_fixture
    mv "$fixture/results/demo" "$fixture/results/$package"
    printf '%s\n' "$package" >"$fixture/results/checked-packages"
    printf '%s\n' "$package" >"$fixture/results/successful-packages"
    git -C "$fixture/repo" diff --binary -- "$package/Staplerfile" \
        >"$fixture/results/$package/update.patch"
    git -C "$fixture/repo" restore -- "$package/Staplerfile"
    detected="$(jq -cn --arg package "$package" '[$package]')"
    expected="$(jq -cn --arg package "$package" --arg latest "$latest" --arg fingerprint "$fingerprint_b" \
        '{($package):{current:"0.3.0.git20260525192209",latest:$latest,fingerprints:{source_fingerprint:$fingerprint}}}')"
    run_validator "$detected" "$expected" >/dev/null
    unexpected="$(jq '.[] .fingerprints.source_fingerprint = ("c" * 64)' <<<"$expected")"
    expect_failure unplanned-plugin-commit run_validator "$detected" "$unexpected"
    # A forged commit cannot hide behind a valid planned digest field.
    sed -i "s/^+upstream_commit='$commit_b'$/+upstream_commit='$(printf 'c%.0s' {1..40})'/" \
        "$fixture/results/$package/update.patch"
    expect_failure forged-plugin-commit run_validator "$detected" "$expected"
done

echo 'OK: строгая проверка update artifact отклоняет подмену и неполные результаты'
