#!/bin/bash

set -euo pipefail

optional_refresh() {
    local label=$1
    shift

    if ! "$@"; then
        echo "Предупреждение: не удалось обновить ${label}." >&2
    fi
}

# Обновляем MIME-базу данных
if command -v update-mime-database &>/dev/null; then
    optional_refresh "MIME-базу" update-mime-database /usr/share/mime
fi

# Обновляем desktop базу данных
if command -v update-desktop-database &>/dev/null; then
    optional_refresh "desktop-базу" update-desktop-database -q /usr/share/applications
fi

# Обновляем кэш иконок
if command -v gtk-update-icon-cache &>/dev/null; then
    optional_refresh "кэш иконок" gtk-update-icon-cache -f -q /usr/share/icons/hicolor
fi

if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    systemctl daemon-reload
    systemctl enable --now happd.service
fi
