#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/nivora-go-build.XXXXXX")"
cleanup() {
    find "$scratch" -mindepth 1 -delete
    rmdir "$scratch"
}
trap cleanup EXIT
mkdir -p "$scratch/bin" "$scratch/source" "$scratch/work dir"
printf 'module example.invalid/tool\n\ngo 1.25.0\n' >"$scratch/source/go.mod"

cat >"$scratch/bin/go" <<'GO'
#!/bin/bash
set -euo pipefail
[[ "$1" == -C && "$2" == "$NIVORA_TEST_GO_CHECKOUT" ]]
shift 2
[[ "$GOTOOLCHAIN" == local && "$GOWORK" == off ]]
[[ "$GOSUMDB" == sum.golang.org ]]
case "$1 $2" in
'mod download')
    printf 'download\n' >>"$NIVORA_TEST_GO_LOG"
    [[ "$GOPROXY" == https://proxy.example.invalid ]]
    attempts="$(grep -c '^download$' "$NIVORA_TEST_GO_LOG")"
    case "$NIVORA_TEST_GO_MODE" in
    transient)
        if ((attempts < 3)); then
            echo 'stream error: INTERNAL_ERROR; received from peer' >&2
            exit 1
        fi
        ;;
    unavailable) echo 'proxy: 503 Service Unavailable' >&2; exit 1 ;;
    timeout) exit 124 ;;
    checksum) echo 'verifying module: checksum mismatch; SECURITY ERROR' >&2; exit 1 ;;
    changed-module) printf '\nrequire example.invalid/new v1.0.0\n' >>"$NIVORA_TEST_GO_CHECKOUT/go.mod" ;;
    esac
    ;;
'mod verify')
    printf 'verify\n' >>"$NIVORA_TEST_GO_LOG"
    [[ "$GOPROXY" == off && "$GONOPROXY" == none ]]
    if [[ "$NIVORA_TEST_GO_MODE" == damaged-cache ]]; then
        echo 'dependency dir has been modified' >&2
        exit 1
    fi
    ;;
'build -mod=readonly')
    printf 'build\n' >>"$NIVORA_TEST_GO_LOG"
    [[ "$GOPROXY" == off && "$GONOPROXY" == none ]]
    [[ "$3" == -trimpath && "$4" == -o && "$6" == ./cmd/tool ]]
    candidate="$5"
    [[ "$candidate" == "$NIVORA_TEST_GO_TARGET".tmp.* ]]
    if [[ "$NIVORA_TEST_GO_MODE" == compiler-error ]]; then
        printf 'incomplete binary\n' >"$candidate"
        echo 'undefined: brokenSymbol' >&2
        exit 1
    fi
    [[ "$NIVORA_TEST_GO_MODE" != empty-output ]] || exit 0
    cat >"$candidate" <<'BINARY'
#!/bin/bash
set -euo pipefail
[[ "$1" == --help ]]
printf 'smoke\n' >>"$NIVORA_TEST_GO_LOG"
[[ "$NIVORA_TEST_GO_MODE" != broken-binary ]] || exit 7
echo 'ready tool'
BINARY
    chmod +x "$candidate"
    ;;
*) echo "unexpected Go call: $*" >&2; exit 99 ;;
esac
GO

cat >"$scratch/bin/timeout" <<'TIMEOUT'
#!/bin/bash
set -euo pipefail
[[ "$1" == --signal=TERM && "$2" == --kill-after=5s ]]
printf '%s\n' "$3" >>"$NIVORA_TEST_GO_TIMEOUT_LOG"
[[ "$3" == 180s || "$3" == 30s ]]
shift 3
exec "$@"
TIMEOUT
cat >"$scratch/bin/sleep" <<'SLEEP'
#!/bin/sh
printf '%s\n' "$1" >>"$NIVORA_TEST_GO_SLEEP_LOG"
SLEEP
chmod +x "$scratch/bin/"*
export PATH="$scratch/bin:$PATH"
export NIVORA_TEST_GO_CHECKOUT="$scratch/source"
export NIVORA_TEST_GO_TARGET="$scratch/work dir/tool"
export NIVORA_TEST_GO_LOG="$scratch/go.log"
export NIVORA_TEST_GO_TIMEOUT_LOG="$scratch/timeout.log"
export NIVORA_TEST_GO_SLEEP_LOG="$scratch/sleep.log"
export GOTOOLCHAIN=auto GOWORK="$scratch/foreign.work"
export GOPROXY=https://proxy.example.invalid GONOPROXY='*.example.invalid'
export GOSUMDB=sum.golang.org
source "$repo_root/.github/tools/lib/go_build.sh"

reset_case() {
    : >"$NIVORA_TEST_GO_LOG"
    : >"$NIVORA_TEST_GO_TIMEOUT_LOG"
    : >"$NIVORA_TEST_GO_SLEEP_LOG"
    printf 'previous working binary\n' >"$NIVORA_TEST_GO_TARGET"
    chmod 0755 "$NIVORA_TEST_GO_TARGET"
    printf 'module example.invalid/tool\n\ngo 1.25.0\n' >"$scratch/source/go.mod"
}

# Two failed downloads are retried; cache verification, compilation and smoke
# each run once. A relative target (including spaces) belongs to the caller.
reset_case
export NIVORA_TEST_GO_MODE=transient
(
    cd "$scratch"
    nivora_build_go_binary "$scratch/source" 'work dir/tool' ./cmd/tool --help
) >"$scratch/success.out" 2>"$scratch/success.err"
[[ "$(cat "$NIVORA_TEST_GO_LOG")" == $'download\ndownload\ndownload\nverify\nbuild\nsmoke' ]]
[[ "$(cat "$NIVORA_TEST_GO_TIMEOUT_LOG")" == $'180s\n180s\n180s\n30s' ]]
[[ "$(cat "$NIVORA_TEST_GO_SLEEP_LOG")" == $'1\n2' ]]
[[ -x "$NIVORA_TEST_GO_TARGET" ]]
grep -Fq "echo 'ready tool'" "$NIVORA_TEST_GO_TARGET"
[[ "$(printenv GOTOOLCHAIN)" == auto && "$(printenv GOWORK)" == "$scratch/foreign.work" ]]
[[ "$(printenv GOPROXY)" == https://proxy.example.invalid && "$(printenv GONOPROXY)" == '*.example.invalid' ]]

for mode in unavailable timeout checksum changed-module damaged-cache compiler-error empty-output broken-binary; do
    reset_case
    export NIVORA_TEST_GO_MODE="$mode"
    if nivora_build_go_binary "$scratch/source" "$NIVORA_TEST_GO_TARGET" ./cmd/tool --help \
        >"$scratch/$mode.out" 2>"$scratch/$mode.err"; then
        echo "Go preparation accepted ${mode}" >&2
        exit 1
    fi
    grep -Fxq 'previous working binary' "$NIVORA_TEST_GO_TARGET"
    [[ "$(stat -c %a "$NIVORA_TEST_GO_TARGET")" == 755 ]]
    [[ -z "$(find "$scratch/work dir" -name '*.tmp.*' -print -quit)" ]]
    case "$mode" in
    unavailable | timeout)
        [[ "$(cat "$NIVORA_TEST_GO_LOG")" == $'download\ndownload\ndownload' ]]
        [[ "$(cat "$NIVORA_TEST_GO_SLEEP_LOG")" == $'1\n2' ]]
        ;;
    checksum | changed-module)
        [[ "$(cat "$NIVORA_TEST_GO_LOG")" == download ]]
        [[ ! -s "$NIVORA_TEST_GO_SLEEP_LOG" ]]
        ;;
    damaged-cache)
        [[ "$(cat "$NIVORA_TEST_GO_LOG")" == $'download\nverify' ]]
        ;;
    compiler-error | empty-output)
        [[ "$(cat "$NIVORA_TEST_GO_LOG")" == $'download\nverify\nbuild' ]]
        ;;
    broken-binary)
        [[ "$(cat "$NIVORA_TEST_GO_LOG")" == $'download\nverify\nbuild\nsmoke' ]]
        ;;
    esac
done

# A directory must not be treated as an alternate output location by go build.
reset_case
if nivora_build_go_binary "$scratch/source" "$scratch/work dir" ./cmd/tool --help \
    >"$scratch/directory.out" 2>"$scratch/directory.err"; then
    echo 'Go preparation accepted a directory target' >&2
    exit 1
fi
[[ ! -s "$NIVORA_TEST_GO_LOG" ]]
grep -Fq 'target is a directory' "$scratch/directory.err"

echo 'OK: bounded Go downloads, integrity checks, single build and atomic tool replacement'
