#!/bin/bash

set -euo pipefail

optional_refresh() {
    local label=$1
    shift

    if ! "$@"; then
        echo "Предупреждение: не удалось обновить ${label}." >&2
    fi
}

if command -v update-mime-database &>/dev/null; then
    optional_refresh "MIME-базу" update-mime-database /usr/share/mime
fi

if command -v update-desktop-database &>/dev/null; then
    optional_refresh "desktop-базу" update-desktop-database -q /usr/share/applications
fi

if command -v gtk-update-icon-cache &>/dev/null; then
    optional_refresh "кэш иконок" gtk-update-icon-cache -f -q /usr/share/icons/hicolor
fi

# Stapler maps this script to RPM %post, which runs on a first install and on
# every upgrade alike. RPM passes the resulting number of installed instances:
# 1 on a first install, 2 or more on an upgrade.
transaction_count="${1:-1}"

if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    optional_refresh "unit-файлы" systemctl daemon-reload
    if [[ "$transaction_count" -le 1 ]]; then
        optional_refresh "happd.service" systemctl enable --now happd.service
    else
        # Never re-enable a unit the user deliberately switched off. The
        # running daemon still holds the previous binary, so an active service
        # is restarted onto the new one and an inactive one is left alone.
        optional_refresh "happd.service" systemctl try-restart happd.service
    fi
fi
