#!/bin/bash

set -euo pipefail

optional_refresh() {
    local label=$1
    shift
    if ! "$@"; then
        echo "Предупреждение: не удалось обновить ${label}." >&2
    fi
}

sandbox=/usr/lib/balena-etcher/chrome-sandbox
if [[ ! -f "$sandbox" ]]; then
    echo "Ошибка: не найден Electron sandbox: ${sandbox}" >&2
    exit 1
fi
if [[ -L /proc/self/ns/user ]] && command -v unshare >/dev/null 2>&1 \
    && unshare --user true 2>/dev/null; then
    chmod 0755 "$sandbox"
else
    chmod 4755 "$sandbox"
fi

if command -v update-desktop-database >/dev/null 2>&1; then
    optional_refresh "desktop-базу" update-desktop-database -q /usr/share/applications
fi
if command -v kbuildsycoca6 >/dev/null 2>&1; then
    optional_refresh "кэш KDE" kbuildsycoca6 --noincremental
elif command -v kbuildsycoca5 >/dev/null 2>&1; then
    optional_refresh "кэш KDE" kbuildsycoca5 --noincremental
fi
