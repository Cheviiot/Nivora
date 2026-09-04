#!/bin/bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

grep -Eq 'chmod 4755 .*chrome-sandbox' "${package_dir}/Staplerfile"
grep -Fq "chmod 4755 \"\$sandbox\"" "${package_dir}/postinstall.sh"
if grep -Fq 'unshare --user' "${package_dir}/postinstall.sh"; then
    exit 1
fi
