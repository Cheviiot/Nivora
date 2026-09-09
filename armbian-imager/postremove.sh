#!/bin/bash
set -euo pipefail

optional_refresh() {
    local label=$1
    shift
    if ! "$@"; then
        echo "Предупреждение: не удалось обновить ${label}." >&2
    fi
}

if command -v update-desktop-database >/dev/null 2>&1; then
    optional_refresh "desktop-базу" update-desktop-database -q /usr/share/applications
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    optional_refresh "кэш иконок" \
        gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor
fi
if command -v kbuildsycoca6 >/dev/null 2>&1; then
    optional_refresh "кэш KDE" kbuildsycoca6 --noincremental
elif command -v kbuildsycoca5 >/dev/null 2>&1; then
    optional_refresh "кэш KDE" kbuildsycoca5 --noincremental
fi
