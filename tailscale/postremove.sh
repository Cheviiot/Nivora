#!/bin/bash

set -euo pipefail

unit=/usr/lib/systemd/system/tailscaled.service

# In postremove, the unit is missing only after a full removal. On an
# upgrade the new version has already put it back, regardless of package format.
if [[ ! -e "$unit" ]] && command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    if systemctl is-active --quiet tailscaled.service; then
        systemctl stop tailscaled.service
    fi
    if systemctl is-enabled --quiet tailscaled.service; then
        systemctl disable tailscaled.service
    fi
    systemctl daemon-reload
fi
