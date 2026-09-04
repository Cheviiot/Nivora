#!/bin/bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
staplerfile="${package_dir}/Staplerfile"

version="$(sed -n 's/^version=//p' "$staplerfile")"
commit="$(sed -n "s/^upstream_commit='\([0-9a-f]\{40\}\)'$/\1/p" "$staplerfile")"

[[ -n "$version" && -n "$commit" ]]
grep -Fq "raw.githubusercontent.com/desktop/desktop/\${upstream_commit}/" "$staplerfile"
if grep -Fq "raw.githubusercontent.com/desktop/desktop/release-\${version}/" "$staplerfile"; then
    exit 1
fi

if [[ -n "${EXPECTED_UPSTREAM_COMMIT:-}" ]]; then
    [[ "$EXPECTED_UPSTREAM_COMMIT" =~ ^[0-9a-f]{40}$ ]]
    [[ "$commit" == "$EXPECTED_UPSTREAM_COMMIT" ]]
elif [[ "${VERIFY_UPSTREAM:-0}" == 1 ]]; then
    resolved="$({
        git ls-remote https://github.com/desktop/desktop.git \
            "refs/tags/release-${version}^{}"
        git ls-remote https://github.com/desktop/desktop.git \
            "refs/tags/release-${version}"
    } | awk 'NR == 1 { print $1 }')"
    [[ "$resolved" == "$commit" ]]
fi
