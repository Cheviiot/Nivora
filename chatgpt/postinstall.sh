#!/bin/bash

set -euo pipefail

optional_refresh() {
    local label=$1
    shift
    if ! "$@"; then
        echo "Предупреждение: не удалось обновить ${label}." >&2
    fi
}

profile=/etc/apparmor.d/chatgpt
disabled=/etc/apparmor.d/disable/chatgpt
if [[ -f /etc/apparmor.d/abi/4.0 ]]; then
    if [[ -L "$disabled" && "$(readlink "$disabled")" == '.././chatgpt' ]]; then
        rm -f "$disabled"
    fi
    if [[ ! -e "$disabled" && ! -L "$disabled" ]] &&
        command -v aa-enabled >/dev/null 2>&1 &&
        command -v apparmor_parser >/dev/null 2>&1 &&
        aa-enabled --quiet; then
        apparmor_parser -r -W -T "$profile"
    fi
elif command -v apparmor_parser >/dev/null 2>&1 &&
    [[ ! -e "$disabled" && ! -L "$disabled" ]]; then
    install -d /etc/apparmor.d/disable
    ln -s '.././chatgpt' "$disabled"
fi

if command -v update-desktop-database >/dev/null 2>&1; then
    optional_refresh "desktop-базу" update-desktop-database -q /usr/share/applications
fi

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    optional_refresh "кэш иконок" gtk-update-icon-cache -f -q /usr/share/icons/hicolor
fi

if command -v kbuildsycoca6 >/dev/null 2>&1; then
    optional_refresh "кэш KDE" kbuildsycoca6 --noincremental
elif command -v kbuildsycoca5 >/dev/null 2>&1; then
    optional_refresh "кэш KDE" kbuildsycoca5 --noincremental
fi
