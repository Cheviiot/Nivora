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
fi
