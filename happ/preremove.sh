#!/bin/bash

set -euo pipefail

# RPM %preun receives the number of installed instances that will remain.
# Stop and disable the daemon only on final removal, while its unit still
# exists. Replacing the old RPM during an upgrade must preserve the tunnel
# and the user's service enablement choice.
[[ "${1:-0}" == 0 ]] || exit 0

if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    systemctl --no-reload disable happd.service >/dev/null 2>&1 || true
    systemctl stop happd.service >/dev/null 2>&1 || true
fi
