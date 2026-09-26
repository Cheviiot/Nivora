#!/bin/bash

set -euo pipefail

# Stapler maps this script to RPM %preun, where $1 is the number of instances
# that will remain: 0 on a real removal, 1 while an upgrade replaces the old
# package. Upstream stops and disables the service only on a real removal, and
# so does this package — an upgrade must not drop an active session.
case "${1:-0}" in
1 | upgrade)
    exit 0
    ;;
esac

if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    systemctl --no-reload disable subnetdesk.service >/dev/null 2>&1 || true
    systemctl stop subnetdesk.service >/dev/null 2>&1 || true
fi
