#!/bin/bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
staplerfile="${package_dir}/Staplerfile"

grep -Fq "\${pkgdir}/usr/lib/chatgpt/ChatGPT" "$staplerfile"
grep -Fq 'ln -sfn /usr/lib/chatgpt/ChatGPT' "$staplerfile"
grep -Fq 'Exec=/usr/bin/chatgpt %U' "$staplerfile"
grep -Fq '"/usr/lib/chatgpt/ChatGPT"' "$staplerfile"
grep -Fq 'provides=('"'"'codex'"'"')' "$staplerfile"
grep -Fq 'replaces=('"'"'chatgpt'"'"' '"'"'codex'"'"')' "$staplerfile"
grep -Fq 'conflicts=('"'"'codex'"'"')' "$staplerfile"
# These patterns intentionally contain literal recipe variables.
# shellcheck disable=SC2016
amd64_source_pattern='chatgpt_amd64.deb?nivora=${source_fingerprint_amd64}'
# shellcheck disable=SC2016
arm64_source_pattern='chatgpt_arm64.deb?nivora=${source_fingerprint_arm64}'
grep -Fq "$amd64_source_pattern" "$staplerfile"
grep -Fq "$arm64_source_pattern" "$staplerfile"
if grep -Fq '/opt/chatgpt' "$staplerfile"; then
    exit 1
fi
