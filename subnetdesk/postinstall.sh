#!/bin/bash

set -euo pipefail

# Stapler maps this script to RPM %post, which runs on a first install and on
# every upgrade alike. RPM passes the resulting number of installed instances:
# 1 on a first install, 2 or more on an upgrade.
transaction_count="${1:-1}"

optional_refresh() {
    local label=$1
    shift
    if ! "$@"; then
        echo "Предупреждение: не удалось обновить ${label}." >&2
    fi
}

optional_step() {
    local label=$1
    shift
    if ! "$@"; then
        echo "Предупреждение: ${label}." >&2
    fi
}

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

if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    optional_step 'не удалось перечитать unit-файлы' systemctl daemon-reload
    if [[ "$transaction_count" -le 1 ]]; then
        # Both the upstream .deb and the upstream .rpm enable and start the
        # service in their own postinstall: without it the machine can only
        # control others, never be controlled. ALT's preset policy ends with
        # 'disable *', so `systemctl preset` would leave it off.
        optional_step 'не удалось включить subnetdesk.service' \
            systemctl enable --now subnetdesk.service
    else
        # Never re-enable a unit the user deliberately switched off. A running
        # daemon still holds the previous binary, so an active service is
        # restarted onto the new one and an inactive one is left alone.
        optional_step 'не удалось перезапустить subnetdesk.service' \
            systemctl try-restart subnetdesk.service
    fi
fi

if [[ "$transaction_count" -le 1 ]]; then
    cat >&2 <<'HINT'

SubnetDesk установлен, служба subnetdesk запущена.

Приложение работает только внутри локальной сети или VPN: публичных
rendezvous- и relay-серверов у него нет, подключение идёт по адресу узла.

Чтобы этой машиной можно было управлять, задайте постоянный пароль в
окне приложения (Настройки → Безопасность) либо отключите службу, если
входящие подключения не нужны:

    sudo systemctl disable --now subnetdesk.service

HINT
fi
