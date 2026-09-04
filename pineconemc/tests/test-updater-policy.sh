#!/bin/bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
recipe="${package_dir}/Staplerfile"

# Assert the literal Stapler package() expression.
# shellcheck disable=SC2016
grep -Fq 'rm -f "${pkgdir}/opt/pineconemc/bin/elyprismlauncher_updater"' \
    "$recipe"
if grep -Fq 'install -Dm755 /dev/stdin' "$recipe"; then
    echo 'PineconeMC updater must be absent, not replaced with a failing stub' >&2
    exit 1
fi

echo 'OK: PineconeMC self-updater is disabled by absence'
