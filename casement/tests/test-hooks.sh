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
if [[ "$(basename "$0")" == systemctl && -n "${CASEMENT_SYSTEMCTL_FAIL_UID:-}" ]]; then
	for argument in "$@"; do
		[[ "$argument" != "--machine=${CASEMENT_SYSTEMCTL_FAIL_UID}@.host" ]] || exit 1
	done
fi
MOCK
	chmod 0755 "${mock_bin}/${command}"
done
cat >"${mock_bin}/loginctl" <<'MOCK'
#!/bin/bash
printf '%s\n' "$*" >>"${CASEMENT_LOGINCTL_LOG:?}"
[[ "${CASEMENT_LOGINCTL_FAIL:-0}" != 1 ]] || exit 1
cat "${CASEMENT_LOGINCTL_USERS:?}"
MOCK
chmod 0755 "${mock_bin}/loginctl"

export PATH="${mock_bin}:/usr/bin:/bin"
export CASEMENT_HOOK_LOG="${work_dir}/calls.log"
export CASEMENT_LOGINCTL_LOG="${work_dir}/loginctl.log"
export CASEMENT_LOGINCTL_USERS="${work_dir}/users.txt"
: >"$CASEMENT_HOOK_LOG"
: >"$CASEMENT_LOGINCTL_LOG"
printf '1000 alice\n1001 no-manager\ninvalid uid\n1002;touch-marker injected\n' \
	>"$CASEMENT_LOGINCTL_USERS"

bash "${package_dir}/postinstall.sh" 1
grep -Fxq 'systemctl --global enable casement-host.service' "$CASEMENT_HOOK_LOG"
test ! -s "$CASEMENT_LOGINCTL_LOG"

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
if grep -Fq 'systemctl --user --machine=' "$CASEMENT_HOOK_LOG" ||
	[[ -s "$CASEMENT_LOGINCTL_LOG" ]]; then
	echo 'upgrade contacted active user managers' >&2
	exit 1
fi

: >"$CASEMENT_HOOK_LOG"
export CASEMENT_SYSTEMCTL_FAIL_UID=1001
bash "${package_dir}/preremove.sh" 0 2>"${work_dir}/remove-warnings.log"
grep -Fxq 'systemctl --global disable casement-host.service' "$CASEMENT_HOOK_LOG"
grep -Fxq 'systemctl --user --machine=1000@.host stop casement-host.service' "$CASEMENT_HOOK_LOG"
grep -Fxq 'systemctl --user --machine=1001@.host stop casement-host.service' "$CASEMENT_HOOK_LOG"
if grep -Fq 'systemctl --user --machine=invalid@.host' "$CASEMENT_HOOK_LOG" ||
	grep -Fq 'systemctl --user --machine=1002;touch-marker@.host' "$CASEMENT_HOOK_LOG"; then
	echo 'invalid user ID reached systemctl' >&2
	exit 1
fi
grep -Fq 'не удалось остановить Casement в сеансе UID 1001' \
	"${work_dir}/remove-warnings.log"
grep -Fxq 'list-users --no-legend --no-pager' "$CASEMENT_LOGINCTL_LOG"

# Failure to enumerate users or connect to one user's bus must not block RPM removal.
: >"$CASEMENT_HOOK_LOG"
: >"$CASEMENT_LOGINCTL_LOG"
CASEMENT_LOGINCTL_FAIL=1 bash "${package_dir}/preremove.sh" 0 \
	2>"${work_dir}/list-users-warnings.log"
grep -Fxq 'systemctl --global disable casement-host.service' "$CASEMENT_HOOK_LOG"
if grep -Fq 'systemctl --user --machine=' "$CASEMENT_HOOK_LOG"; then
	echo 'user manager stop ran after loginctl failed' >&2
	exit 1
fi
grep -Fq 'не удалось получить список пользовательских сеансов' \
	"${work_dir}/list-users-warnings.log"

# Every service-manager and desktop-cache command above is a temporary mock;
# the test never contacts the running user session or changes the host desktop.
echo 'OK: Casement hooks preserve upgrades and stop active user services on removal'
