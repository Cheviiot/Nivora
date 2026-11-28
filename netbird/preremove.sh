#!/bin/bash

set -euo pipefail

# RPM %preun receives zero only on final removal.
[[ "${1:-0}" == 0 ]] || exit 0

if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    systemctl --no-reload disable netbird.service >/dev/null 2>&1 || true
    systemctl stop netbird.service >/dev/null 2>&1 || true
fi
