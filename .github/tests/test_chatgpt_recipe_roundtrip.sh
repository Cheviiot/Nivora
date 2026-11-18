#!/bin/bash
# Updating metadata must not make the formatter change the DEB payload guard.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -f -- "$fixture/Staplerfile"; rmdir -- "$fixture"' EXIT
cp "$repo_root/chatgpt/Staplerfile" "$fixture/Staplerfile"
version="$(stplr-spec get-field --path "$fixture/Staplerfile" version)"
stplr-spec set-field --path "$fixture/Staplerfile" version "$version"
# Match the updater's existing normalization of the version assignment only.
sed -i -E "s/^version=([^'\"#]+)$/version='\\1'/" "$fixture/Staplerfile"
if ! diff -u "$repo_root/chatgpt/Staplerfile" "$fixture/Staplerfile"; then
    echo 'ChatGPT metadata update reformats recipe code; keep the recipe in stplr-spec canonical style' >&2
    exit 1
fi

echo 'OK: ChatGPT metadata round-trip preserves the payload guard and recipe code'
