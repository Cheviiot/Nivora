#!/bin/bash

set -euo pipefail

unit=/usr/lib/systemd/system/netbird.service

if [[ ! -e "$unit" ]] && command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    if systemctl is-active --quiet netbird.service; then
        systemctl stop netbird.service
    fi
    if systemctl is-enabled --quiet netbird.service; then
        systemctl disable netbird.service
    fi
    systemctl daemon-reload
fi
