#!/bin/bash

# Prepare dependencies separately so a transient module transfer never reruns
# compilation. Publish only a complete binary that passes its caller's smoke.
nivora_build_go_binary() (
    set -euo pipefail
    local go_checkout="${1:?usage: nivora_build_go_binary CHECKOUT TARGET PACKAGE [SMOKE_ARGS...]}"
    local go_target="${2:?usage: nivora_build_go_binary CHECKOUT TARGET PACKAGE [SMOKE_ARGS...]}"
    local go_package="${3:?usage: nivora_build_go_binary CHECKOUT TARGET PACKAGE [SMOKE_ARGS...]}"
    shift 3
    local command attempt status=1 downloaded=false log='' candidate='' module_digest

    for command in go timeout; do
        command -v "$command" >/dev/null 2>&1 || {
            echo "Go preparation requires ${command}" >&2
            exit 2
        }
    done
    [[ "$go_target" == /* ]] || go_target="${PWD}/${go_target}"
    [[ ! -d "$go_target" ]] || {
        echo "Go preparation target is a directory: ${go_target}" >&2
        exit 2
    }
    module_digest="$(sha256sum "$go_checkout/go.mod")" || exit
    install -d -- "$(dirname "$go_target")" || exit
    log="$(mktemp "${TMPDIR:-/tmp}/nivora-go-download.XXXXXX")" || exit
    trap '[[ -z "$candidate" ]] || rm -f -- "$candidate"; rm -f -- "$log"' EXIT

    # A local go.work or automatic toolchain download must not change the pin.
    export GOTOOLCHAIN=local GOWORK=off
    for attempt in 1 2 3; do
        if timeout --signal=TERM --kill-after=5s 180s \
            go -C "$go_checkout" mod download >"$log" 2>&1; then
            cat "$log"
            downloaded=true
            break
        else
            status="$?"
            cat "$log" >&2
        fi
        # Retrying cannot repair an integrity failure. Keep the evidence/cache
        # intact instead of deleting it or weakening checksum verification.
        if grep -Eq 'checksum mismatch|SECURITY ERROR' "$log"; then
            exit "$status"
        fi
        case "$status" in 129 | 130 | 131 | 143) exit "$status" ;; esac
        echo "Go dependency download attempt ${attempt}/3 failed (exit ${status})" >&2
        if ((attempt < 3)); then
            sleep "$attempt"
        fi
    done
    [[ "$downloaded" == true ]] || exit "$status"
    [[ "$(sha256sum "$go_checkout/go.mod")" == "$module_digest" ]] || {
        echo 'Go dependency download changed the pinned go.mod; update the upstream pin explicitly' >&2
        exit 1
    }

    # Validate the extracted cache once; compilation must use that cache and
    # must not silently add dependencies or fall back to a direct VCS download.
    export GOPROXY=off GONOPROXY=none
    go -C "$go_checkout" mod verify || exit
    candidate="$(mktemp "${go_target}.tmp.XXXXXX")" || exit
    go -C "$go_checkout" build -mod=readonly -trimpath -o "$candidate" "$go_package" || exit
    [[ -s "$candidate" ]] || {
        echo "Go preparation produced an empty binary: ${go_package}" >&2
        exit 1
    }
    chmod 0755 "$candidate" || exit
    if (($#)); then
        timeout --signal=TERM --kill-after=5s 30s "$candidate" "$@" >/dev/null || exit
    fi
    mv -fT -- "$candidate" "$go_target" || exit
    candidate=''
)
