#!/bin/bash

set -euo pipefail

optional_refresh() {
	local label=$1
	shift
	if ! "$@"; then
		echo "Предупреждение: не удалось обновить ${label}." >&2
	fi
}

if command -v update-desktop-database >/dev/null 2>&1; then
	optional_refresh 'desktop-базу' update-desktop-database -q /usr/share/applications
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
	optional_refresh 'кэш иконок' gtk-update-icon-cache -f -q /usr/share/icons/hicolor
fi

# The upstream RPM enables this unit globally on every install, including
# upgrades. Enable it only on the first install so an administrator's later
# choice to disable the user service survives package updates.
transaction_count="${1:-1}"
if [[ "$transaction_count" -le 1 ]] && command -v systemctl >/dev/null 2>&1; then
	optional_refresh 'автозагрузку Casement для пользовательских сеансов' \
		systemctl --global enable casement-host.service
fi
