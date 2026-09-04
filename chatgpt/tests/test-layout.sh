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
if grep -Fq '/opt/chatgpt' "$staplerfile"; then
    exit 1
fi
