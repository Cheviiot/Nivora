#!/bin/bash
set -euo pipefail

sandbox=/opt/github-desktop/chrome-sandbox
if [[ -f "$sandbox" ]]; then
    if [[ -L /proc/self/ns/user ]] && command -v unshare >/dev/null 2>&1 \
        && unshare --user true 2>/dev/null; then
        chmod 0755 "$sandbox"
    else
        chmod 4755 "$sandbox"
    fi
fi

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database -q /usr/share/applications || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -q /usr/share/icons/hicolor || true
fi
