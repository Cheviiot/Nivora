#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
matrix="${repo_root}/.github/support-matrix.toml"
target="${1:?usage: prepare_stplr.sh TARGET}"
channel="${NIVORA_STPLR_CHANNEL:-stable}"
# shellcheck source=.github/tools/lib/pinned_git_checkout.sh
source "${script_dir}/lib/pinned_git_checkout.sh"
# shellcheck source=.github/tools/lib/go_build.sh
source "${script_dir}/lib/go_build.sh"

# Resolve against the caller before preparing any checkout or candidate.
[[ "$target" == /* ]] || target="${PWD}/${target}"
[[ ! -d "$target" ]] || {
    echo "stplr target is a directory: ${target}" >&2
    exit 2
}

read_matrix() {
    python3 - "$matrix" "$1" <<'PY'
import sys, tomllib
with open(sys.argv[1], "rb") as stream:
    value = tomllib.load(stream)["stapler"][sys.argv[2]]
print(value)
PY
}

install -d "$(dirname "$target")"
case "$channel" in
stable)
    version="$(read_matrix stable_version)"
    case "$(uname -m)" in
    x86_64) architecture=x86_64 ;;
    aarch64 | arm64) architecture=aarch64 ;;
    *)
        echo "Unsupported architecture for pinned stable stplr: $(uname -m)" >&2
        exit 2
        ;;
    esac
    url="$(read_matrix "stable_linux_${architecture}_url")"
    expected="$(read_matrix "stable_linux_${architecture}_sha256")"
    [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || {
        echo "stplr v${version}: invalid pinned SHA-256 for ${architecture}" >&2
        exit 2
    }
    cache_dir="${NIVORA_STPLR_CACHE_DIR:-${XDG_CACHE_HOME:-${HOME}/.cache}/nivora/stplr}"
    archive="${cache_dir}/stplr-${version}-linux-${architecture}.tar.gz"
    install -d -m0755 "$cache_dir"
    download=''
    candidate=''
    cleanup_archive() {
        [[ -z "$download" ]] || rm -f -- "$download"
        [[ -z "$candidate" ]] || rm -f -- "$candidate"
    }
    trap cleanup_archive EXIT
    actual=''
    if [[ -f "$archive" ]]; then
        actual="$(sha256sum "$archive")"
        actual="${actual%% *}"
    fi
    if [[ "$actual" != "$expected" ]]; then
        download="$(mktemp "${cache_dir}/.stplr-${version}.XXXXXX")"
        curl -fL --retry 3 --retry-all-errors --connect-timeout 20 --max-time 300 \
            -o "$download" "$url"
        actual="$(sha256sum "$download")"
        actual="${actual%% *}"
        [[ "$actual" == "$expected" ]] || {
            echo "stplr v${version}: SHA-256 mismatch: ${actual}" >&2
            exit 1
        }
        chmod 0644 "$download"
        mv -f -- "$download" "$archive"
        download=''
    fi
    candidate="$(mktemp "${target}.tmp.XXXXXX")"
    tar -xOf "$archive" stplr >"$candidate"
    chmod 0755 "$candidate"
    version_output="$(timeout --signal=TERM --kill-after=5s 30s "$candidate" version)"
    mv -fT -- "$candidate" "$target"
    candidate=''
    printf '%s\n' "$version_output"
    ;;
main)
    for command in git go; do
        command -v "$command" >/dev/null 2>&1 || {
            echo "Pinned main canary requires ${command}" >&2
            exit 2
        }
    done
    repository="$(read_matrix main_repository)"
    commit="$(read_matrix main_commit)"
    checkout="$(mktemp -d)"
    cleanup_checkout() {
        find "$checkout" -mindepth 1 -delete
        rmdir "$checkout"
    }
    trap cleanup_checkout EXIT
    pinned_git_checkout "$repository" "$commit" "$checkout"
    nivora_build_go_binary "$checkout" "$target" ./cmd/stplr version
    printf 'Prepared Stapler main at %s\n' "$commit"
    ;;
*)
    echo "Unknown NIVORA_STPLR_CHANNEL: ${channel}" >&2
    exit 2
    ;;
esac
