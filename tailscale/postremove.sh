#!/bin/bash

set -euo pipefail

# Stopping and disabling the daemon belongs to preremove, which RPM runs while
# it still knows whether this is a removal or an upgrade. Here only the unit
# files have changed on disk, so the single job left is telling systemd to
# reread them.
if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    systemctl daemon-reload >/dev/null 2>&1 || true
fi
