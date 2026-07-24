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
for alias in nv nvi nve nvu nvs nvqi nvqa nvr nvrl nvf nvd nvc; do
    ln -s "${repo_root}/nivora-cli/nivora" "${temp_dir}/bin/${alias}"
done

export NIVORA_TEST_LOG="$log"
export NIVORA_SUDO='test-sudo'
export NIVORA_QUIET=1
export PATH="${temp_dir}/bin:${PATH}"

nvi codex --clean
nve other/package
nvu
nvs editor
nvqi --json codex
nvqa --installed
nvr
nvrl
nvf
nvc
nv --repo none install local-name

cat >"${temp_dir}/expected" <<'EOF'
sudo stplr install nivora/codex --clean
stplr install nivora/codex --clean
sudo stplr remove other/package
stplr remove other/package
sudo stplr up
stplr up
stplr search editor
stplr info --json nivora/codex
stplr list --installed
sudo stplr refresh
stplr refresh
stplr repo list
sudo stplr fix
stplr fix
stplr config show
sudo stplr install local-name
stplr install local-name
EOF

diff -u "${temp_dir}/expected" "$log"

nv --lang en --help >"${temp_dir}/help-en"
nv --lang ru --help >"${temp_dir}/help-ru"
nv --lang ru completion fish >"${temp_dir}/completion"
nvd --lang en >"${temp_dir}/doctor"
NIVORA_QUIET=0 nv --lang en --dry-run install codex \
    >"${temp_dir}/preview-stdout" 2>"${temp_dir}/preview"

grep -q 'Simple Stapler package management' "${temp_dir}/help-en"
grep -q 'Простое управление пакетами Stapler' "${temp_dir}/help-ru"
grep -q 'nvi.*установить' "${temp_dir}/help-ru"
grep -q '__fish_use_subcommand' "${temp_dir}/completion"
grep -q 'The system is ready' "${temp_dir}/doctor"
grep -q 'Preview.*test-sudo stplr install nivora/codex' "${temp_dir}/preview"
[[ ! -s "${temp_dir}/preview-stdout" ]]

if nv --lang de help >"${temp_dir}/invalid-out" 2>"${temp_dir}/invalid"; then
    echo 'Ожидалась ошибка для неподдерживаемого языка' >&2
    exit 1
fi
grep -q 'supported languages are ru and en' "${temp_dir}/invalid"

echo 'OK: Nivora CLI'
