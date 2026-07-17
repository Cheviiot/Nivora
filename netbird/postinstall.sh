#!/bin/bash

set -euo pipefail

legacy_unit=/etc/systemd/system/netbird.service
if [[ -f "$legacy_unit" ]] && grep -Fq 'ExecStart=/usr/bin/netbird "service" "run"' "$legacy_unit"; then
    rm -f -- "$legacy_unit"
fi

if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    systemctl daemon-reload
    systemctl enable --now netbird.service
fi
