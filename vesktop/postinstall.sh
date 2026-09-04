#!/bin/bash

set -euo pipefail

optional_refresh() {
    local label=$1
    shift
    if ! "$@"; then
        echo "Предупреждение: не удалось обновить ${label}." >&2
    fi
}

sandbox=/opt/Vesktop/chrome-sandbox
if [[ ! -f "$sandbox" ]]; then
    echo "Ошибка: не найден Electron sandbox: ${sandbox}" >&2
    exit 1
fi
# Maintainer scripts run as root, so probing unshare here says nothing about
# whether the desktop user may create a user namespace. Keep Electron's
# setuid helper enabled as the deterministic sandbox fallback for normal users.
chmod 4755 "$sandbox"

if command -v update-desktop-database >/dev/null 2>&1; then
    optional_refresh "desktop-базу" update-desktop-database -q /usr/share/applications
fi
if command -v update-mime-database >/dev/null 2>&1; then
    optional_refresh "базу MIME" update-mime-database /usr/share/mime
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    optional_refresh "кэш иконок" gtk-update-icon-cache -f -q /usr/share/icons/hicolor
fi
if command -v kbuildsycoca6 >/dev/null 2>&1; then
    optional_refresh "кэш KDE" kbuildsycoca6 --noincremental
elif command -v kbuildsycoca5 >/dev/null 2>&1; then
    optional_refresh "кэш KDE" kbuildsycoca5 --noincremental
fi
