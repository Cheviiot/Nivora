#!/bin/bash

set -euo pipefail

optional_refresh() {
    local label=$1
    shift
    if ! "$@"; then
        echo "Предупреждение: не удалось обновить ${label}." >&2
    fi
}

# Обновляем кэш иконок
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    optional_refresh "кэш иконок" gtk-update-icon-cache -f -q /usr/share/icons/hicolor
fi

# Обновляем desktop базу данных
if command -v update-desktop-database >/dev/null 2>&1; then
    optional_refresh "desktop-базу" update-desktop-database -q /usr/share/applications
fi
