#!/bin/bash

set -euo pipefail

systemd_step() {
    if ! systemctl "$@"; then
        printf 'Предупреждение: не удалось выполнить systemctl %s.\n' "$*" >&2
    fi
}

if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    systemd_step daemon-reload
    # RPM %post receives 1 on first install and 2 or more on upgrade.
    if [[ "${1:-1}" == 1 ]]; then
        systemd_step enable --now netbird.service
    else
        systemd_step try-restart netbird.service
    fi
fi

if [[ "${1:-}" == 1 ]]; then
    printf '%s\n' 'Лицензия NetBird — BSD-3-Clause. Условия в /usr/share/licenses/netbird/LICENSE' >&2 || :
fi
