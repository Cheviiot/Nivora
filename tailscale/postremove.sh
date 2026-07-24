#!/bin/bash

set -euo pipefail

unit=/usr/lib/systemd/system/tailscaled.service

# В postremove unit отсутствует только после полного удаления. При обновлении
# новая версия уже вернула его на место, независимо от формата пакета.
if [[ ! -e "$unit" ]] && command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    if systemctl is-active --quiet tailscaled.service; then
        systemctl stop tailscaled.service
    fi
    if systemctl is-enabled --quiet tailscaled.service; then
        systemctl disable tailscaled.service
    fi
    systemctl daemon-reload
fi
