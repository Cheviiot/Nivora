#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/nivora-alt-builder-test.XXXXXX")"
trap 'find "$scratch" -mindepth 1 -delete; rmdir "$scratch"' EXIT
mkdir -p "$scratch/lib" "$scratch/images" "$scratch/build" "$scratch/lifecycle"
cp "$repo_root/.github/tools/lib/alt_builder.sh" "$scratch/lib/"
cp "$repo_root/.github/tools/lib/alt_apt_network.sh" "$scratch/lib/"
printf 'stable binary\n' >"$scratch/build/stplr"
cp "$scratch/build/stplr" "$scratch/lifecycle/stplr"
export NIVORA_BUILDER_TEST_ROOT="$scratch"

cat >"$scratch/engine" <<'EOF'
#!/bin/bash
set -euo pipefail
image_path() {
    printf '%s/images/%s' "$NIVORA_BUILDER_TEST_ROOT" \
        "$(printf '%s' "$1" | sha256sum | cut -d ' ' -f 1)"
}
printf '%s\n' "$*" >>"$NIVORA_BUILDER_TEST_ROOT/engine.log"
case "$1" in
pull) exit 0 ;;
build)
    [[ "$2" == -t && "$4" == -f && -s "$5" ]]
    [[ "${NIVORA_BUILDER_TEST_FAIL:-0}" != 1 ]] || exit 1
    printf 'prepared environment\n' >"$(image_path "$3")"
    ;;
tag)
    cp "$(image_path "$2")" "$(image_path "$3")"
    ;;
image)
    case "$2" in
    inspect) [[ -s "$(image_path "$3")" ]] ;;
    rm) rm -f -- "$(image_path "$3")" ;;
    *) exit 2 ;;
    esac
    ;;
*) exit 2 ;;
esac
EOF
chmod +x "$scratch/engine"

# shellcheck source=.github/tools/lib/alt_builder.sh
source "$scratch/lib/alt_builder.sh"
export GITHUB_ACTIONS=true GITHUB_RUN_ID=1234 GITHUB_RUN_ATTEMPT=1
export GITHUB_JOB=stable GITHUB_REPOSITORY=fixture/catalog
base_image="alt-p11@sha256:$(printf 'a%.0s' {1..64})"
engine="$scratch/engine"

assert_builds() {
    local actual
    actual="$(grep -c '^build ' "$scratch/engine.log" || true)"
    [[ "$actual" == "$1" ]] || {
        echo "FAIL: expected $1 preparations, got $actual" >&2
        cat "$scratch/engine.log" >&2
        exit 1
    }
}

nivora_prepare_alt_builder "$engine" p11 "$base_image" "$scratch/build" first:build
"$engine" image rm first:build
nivora_prepare_alt_builder "$engine" p11 "$base_image" "$scratch/lifecycle" second:lifecycle
assert_builds 1
"$engine" image inspect second:lifecycle
cmp "$scratch/build/Containerfile" "$scratch/lifecycle/Containerfile"

# Stable and canary must never share prepared images when their binaries differ.
printf 'canary binary\n' >"$scratch/lifecycle/stplr"
nivora_prepare_alt_builder "$engine" p11 "$base_image" "$scratch/lifecycle" next:canary
assert_builds 2

base_image="alt-p11@sha256:$(printf 'b%.0s' {1..64})"
nivora_prepare_alt_builder "$engine" p11 "$base_image" "$scratch/lifecycle" next:base
assert_builds 3

printf '\n# changed helper\n' >>"$scratch/lib/alt_apt_network.sh"
nivora_prepare_alt_builder "$engine" p11 "$base_image" "$scratch/lifecycle" next:helper
assert_builds 4

export GITHUB_RUN_ATTEMPT=2
nivora_prepare_alt_builder "$engine" p11 "$base_image" "$scratch/lifecycle" next:attempt
assert_builds 5
export GITHUB_JOB=repair
nivora_prepare_alt_builder "$engine" p11 "$base_image" "$scratch/lifecycle" next:job
assert_builds 6
export GITHUB_RUN_ID=1235
nivora_prepare_alt_builder "$engine" p11 "$base_image" "$scratch/lifecycle" next:run
assert_builds 7

# Local commands retain disposable preparation rather than a stale persistent tag.
export GITHUB_ACTIONS=false
nivora_prepare_alt_builder "$engine" p11 "$base_image" "$scratch/lifecycle" local:first
nivora_prepare_alt_builder "$engine" p11 "$base_image" "$scratch/lifecycle" local:second
assert_builds 9

export GITHUB_ACTIONS=true GITHUB_RUN_ID=1236 NIVORA_BUILDER_TEST_FAIL=1
if nivora_prepare_alt_builder "$engine" p11 "$base_image" "$scratch/lifecycle" failed:build; then
    echo 'FAIL: unsuccessful preparation was accepted' >&2
    exit 1
fi
assert_builds 10
export NIVORA_BUILDER_TEST_FAIL=0
nivora_prepare_alt_builder "$engine" p11 "$base_image" "$scratch/lifecycle" retry:build
assert_builds 11

echo 'OK: ALT builder reuse, isolated inputs/job attempts, local cleanup and failed preparation'
