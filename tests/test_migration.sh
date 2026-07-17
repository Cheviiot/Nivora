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
state="${temp_dir}/packages"
repos="${temp_dir}/repos"
log="${temp_dir}/commands"
printf '%s\n' 'codex-app+stplr-luma' 'tailscale+stplr-luma' >"$state"
printf '%s\n' luma nivora >"$repos"

cat >"${temp_dir}/bin/rpm" <<'EOF'
#!/bin/bash
cat "$NIVORA_TEST_STATE"
EOF

cat >"${temp_dir}/bin/stplr" <<'EOF'
#!/bin/bash
set -euo pipefail
printf 'stplr' >>"$NIVORA_TEST_LOG"
printf ' %s' "$@" >>"$NIVORA_TEST_LOG"
printf '\n' >>"$NIVORA_TEST_LOG"

if [[ "$1" == repo && "$2" == list ]]; then
    cat "$NIVORA_TEST_REPOS"
elif [[ "$1" == repo && "$2" == rm ]]; then
    grep -Fxv "$3" "$NIVORA_TEST_REPOS" >"${NIVORA_TEST_REPOS}.new"
    mv "${NIVORA_TEST_REPOS}.new" "$NIVORA_TEST_REPOS"
elif [[ "$1" == --interactive=false && "$2" == install ]]; then
    target="${3#nivora/}"
    case "$target" in
    codex) old=codex-app ;;
    tailscale) old=tailscale ;;
    *) old="$target" ;;
    esac
    grep -Fxv "${old}+stplr-luma" "$NIVORA_TEST_STATE" >"${NIVORA_TEST_STATE}.new"
    printf '%s\n' "${target}+stplr-nivora" >>"${NIVORA_TEST_STATE}.new"
    mv "${NIVORA_TEST_STATE}.new" "$NIVORA_TEST_STATE"
fi
EOF

chmod 0755 "${temp_dir}/bin/rpm" "${temp_dir}/bin/stplr"
export NIVORA_TEST_STATE="$state"
export NIVORA_TEST_REPOS="$repos"
export NIVORA_TEST_LOG="$log"
export PATH="${temp_dir}/bin:/usr/bin:/bin"

bash "$repo_root/nivora-stplr/nivora-migrate-from-luma" --yes

cat >"${temp_dir}/expected-packages" <<'EOF'
codex+stplr-nivora
tailscale+stplr-nivora
EOF
sort -o "$state" "$state"
diff -u "${temp_dir}/expected-packages" "$state"
if grep -Fxq luma "$repos"; then
    echo 'legacy repository was not removed' >&2
    exit 1
fi
grep -Fq 'install nivora/codex' "$log"
grep -Fq 'install nivora/tailscale' "$log"

echo 'OK: migration state machine'
