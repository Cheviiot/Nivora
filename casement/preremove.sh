#!/bin/bash

set -euo pipefail

optional_refresh() {
	local label=$1
	shift
	if ! "$@"; then
		echo "Предупреждение: не удалось ${label}." >&2
	fi
}

# RPM passes 0 on final removal and a positive count during an upgrade.
transaction_count="${1:-0}"
if [[ "$transaction_count" -eq 0 ]] && command -v systemctl >/dev/null 2>&1; then
	optional_refresh 'отключить автозагрузку Casement' \
		systemctl --global disable casement-host.service
	if command -v loginctl >/dev/null 2>&1; then
		if users="$(loginctl list-users --no-legend --no-pager 2>/dev/null)"; then
			while read -r uid _; do
				[[ "$uid" =~ ^[0-9]+$ ]] || continue
				optional_refresh "остановить Casement в сеансе UID ${uid}" \
					systemctl --user --machine="${uid}@.host" \
					stop casement-host.service
			done <<<"$users"
		else
			echo 'Предупреждение: не удалось получить список пользовательских сеансов для остановки Casement.' >&2
		fi
	fi
fi
