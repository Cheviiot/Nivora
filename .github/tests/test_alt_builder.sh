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

# Exercise selection with an isolated PATH so the runner's own installed
# engines cannot accidentally satisfy missing-engine or fallback cases.
selection_bin="$scratch/selection-bin"
mkdir -p "$selection_bin"
export NIVORA_ENGINE_TEST_LOG="$scratch/selection.log"
for candidate in docker podman; do
    cat >"$selection_bin/$candidate" <<'EOF'
#!/bin/bash
set -euo pipefail
name="${0##*/}"
printf '%s %s\n' "$name" "$*" >>"$NIVORA_ENGINE_TEST_LOG"
[[ "$*" == info ]]
exit "${NIVORA_ENGINE_TEST_EXIT:-0}"
EOF
    chmod 0755 "$selection_bin/$candidate"
done
cat >"$selection_bin/timeout" <<'EOF'
#!/bin/bash
set -euo pipefail
[[ "$1" == --signal=TERM && "$2" == --kill-after=1s && "$3" == 30s ]]
shift 3
exec "$@"
EOF
chmod 0755 "$selection_bin/timeout"

: >"$NIVORA_ENGINE_TEST_LOG"
[[ "$(PATH="$selection_bin" GITHUB_ACTIONS=true NIVORA_CONTAINER_ENGINE='' nivora_alt_container_engine)" == docker ]]
[[ "$(cat "$NIVORA_ENGINE_TEST_LOG")" == 'docker info' ]]
: >"$NIVORA_ENGINE_TEST_LOG"
[[ "$(PATH="$selection_bin" GITHUB_ACTIONS=false NIVORA_CONTAINER_ENGINE='' nivora_alt_container_engine)" == podman ]]
[[ "$(cat "$NIVORA_ENGINE_TEST_LOG")" == 'podman info' ]]
: >"$NIVORA_ENGINE_TEST_LOG"
[[ "$(PATH="$selection_bin" GITHUB_ACTIONS=true NIVORA_CONTAINER_ENGINE=podman nivora_alt_container_engine)" == podman ]]
[[ "$(cat "$NIVORA_ENGINE_TEST_LOG")" == 'podman info' ]]

mv "$selection_bin/docker" "$selection_bin/docker.disabled"
: >"$NIVORA_ENGINE_TEST_LOG"
if PATH="$selection_bin" GITHUB_ACTIONS=false NIVORA_CONTAINER_ENGINE=docker \
    nivora_alt_container_engine >"$scratch/selection.out" 2>"$scratch/selection.err"; then
    echo 'FAIL: missing explicit Docker silently fell back to Podman' >&2
    exit 1
fi
[[ ! -s "$NIVORA_ENGINE_TEST_LOG" && ! -s "$scratch/selection.out" ]]
grep -Fq 'docker is not installed' "$scratch/selection.err"
mv "$selection_bin/docker.disabled" "$selection_bin/docker"

for requested in docker ''; do
    : >"$NIVORA_ENGINE_TEST_LOG"
    if PATH="$selection_bin" GITHUB_ACTIONS=true NIVORA_CONTAINER_ENGINE="$requested" \
        NIVORA_ENGINE_TEST_EXIT=23 nivora_alt_container_engine \
        >"$scratch/selection.out" 2>"$scratch/selection.err"; then
        echo 'FAIL: inaccessible selected Docker was accepted' >&2
        exit 1
    fi
    [[ "$(cat "$NIVORA_ENGINE_TEST_LOG")" == 'docker info' ]]
    [[ ! -s "$scratch/selection.out" ]]
    grep -Fq 'docker is unavailable' "$scratch/selection.err"
done

: >"$NIVORA_ENGINE_TEST_LOG"
if PATH="$selection_bin" GITHUB_ACTIONS=true NIVORA_CONTAINER_ENGINE='sudo podman' \
    nivora_alt_container_engine >"$scratch/selection.out" 2>"$scratch/selection.err"; then
    echo 'FAIL: unsupported container-engine override was accepted' >&2
    exit 1
fi
[[ ! -s "$NIVORA_ENGINE_TEST_LOG" && ! -s "$scratch/selection.out" ]]
grep -Fq 'must be docker or podman' "$scratch/selection.err"

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

echo 'OK: ALT engine selection, bounded availability, builder reuse and isolated job attempts'
