#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
package_dir="${repo_root}/casement"
temporary_root="${TMPDIR:-${HOME}/.cache}"
mkdir -p "$temporary_root"
work_dir="$(mktemp -d "${temporary_root%/}/nivora-casement-hooks.XXXXXX")"
cleanup() {
	find "$work_dir" -mindepth 1 -delete
	rmdir "$work_dir"
}
trap cleanup EXIT

mock_bin="${work_dir}/bin"
mkdir -p "$mock_bin"
cat >"${mock_bin}/record-call" <<'MOCK'
#!/bin/bash
printf '%s\n' "$*" >>"${CASEMENT_HOOK_LOG:?}"
MOCK
chmod 0755 "${mock_bin}/record-call"
for command in systemctl update-desktop-database gtk-update-icon-cache; do
	cat >"${mock_bin}/${command}" <<'MOCK'
#!/bin/bash
"$(dirname "$0")/record-call" "$(basename "$0") $*"
MOCK
	chmod 0755 "${mock_bin}/${command}"
done

export PATH="${mock_bin}:/usr/bin:/bin"
export CASEMENT_HOOK_LOG="${work_dir}/calls.log"
: >"$CASEMENT_HOOK_LOG"

bash "${package_dir}/postinstall.sh" 1
grep -Fxq 'systemctl --global enable casement-host.service' "$CASEMENT_HOOK_LOG"

: >"$CASEMENT_HOOK_LOG"
bash "${package_dir}/postinstall.sh" 2
if grep -Fq 'systemctl --global enable casement-host.service' "$CASEMENT_HOOK_LOG"; then
	echo 'upgrade re-enabled the Casement host service' >&2
	exit 1
fi

: >"$CASEMENT_HOOK_LOG"
bash "${package_dir}/preremove.sh" 1
if grep -Fq 'systemctl --global disable casement-host.service' "$CASEMENT_HOOK_LOG"; then
	echo 'upgrade disabled the Casement host service' >&2
	exit 1
fi

: >"$CASEMENT_HOOK_LOG"
bash "${package_dir}/preremove.sh" 0
grep -Fxq 'systemctl --global disable casement-host.service' "$CASEMENT_HOOK_LOG"

# Every service-manager and desktop-cache command above is a temporary mock;
# the test never contacts the running user session or changes the host desktop.
echo 'OK: Casement hooks preserve service choice on upgrade and disable it on removal'
