#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temp_dir="$(mktemp -d)"

cleanup() {
    find "$temp_dir" -mindepth 1 -delete
    rmdir "$temp_dir"
}
trap cleanup EXIT

mkdir -p "${temp_dir}/bin"
log="${temp_dir}/commands.log"

cat >"${temp_dir}/bin/stplr" <<'EOF'
#!/bin/bash
printf 'stplr' >>"$NIVORA_TEST_LOG"
printf ' %s' "$@" >>"$NIVORA_TEST_LOG"
printf '\n' >>"$NIVORA_TEST_LOG"
EOF

cat >"${temp_dir}/bin/test-sudo" <<'EOF'
#!/bin/bash
printf 'sudo' >>"$NIVORA_TEST_LOG"
printf ' %s' "$@" >>"$NIVORA_TEST_LOG"
printf '\n' >>"$NIVORA_TEST_LOG"
exec "$@"
EOF

chmod 0755 "${temp_dir}/bin/"*
for alias in sli slii sl; do
    ln -s "$repo_root/nivora-stplr/nivora-stplr" "${temp_dir}/bin/${alias}"
done

export NIVORA_TEST_LOG="$log"
export NIVORA_STPLR_SUDO=test-sudo
export NIVORA_STPLR_QUIET=1
export PATH="${temp_dir}/bin:${PATH}"

sli --repo nivora parsec --clean
slii nivora/codex

cat >"${temp_dir}/expected" <<'EOF'
sudo stplr install nivora/parsec --clean
stplr install nivora/parsec --clean
stplr info nivora/codex
EOF

diff -u "${temp_dir}/expected" "$log"
echo 'OK: Nivora helper'
