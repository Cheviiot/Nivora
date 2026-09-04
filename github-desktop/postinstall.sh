#!/bin/bash
set -euo pipefail

sandbox=/opt/github-desktop/chrome-sandbox
if [[ -f "$sandbox" ]]; then
    # Maintainer scripts run as root, so probing unshare here says nothing
    # about whether the desktop user may create a user namespace. Keep
    # Electron's setuid helper as the deterministic normal-user fallback.
    chmod 4755 "$sandbox"
fi

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database -q /usr/share/applications || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -q /usr/share/icons/hicolor || true
fi
