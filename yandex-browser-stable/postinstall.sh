#!/bin/bash

set -euo pipefail

optional_refresh() {
    local label=$1
    shift
    if ! "$@"; then
        echo "Предупреждение: не удалось обновить ${label}." >&2
    fi
}

sandbox=/opt/yandex/browser/yandex_browser-sandbox
if [[ ! -f "$sandbox" ]]; then
    echo "Ошибка: не найден Chromium sandbox: ${sandbox}" >&2
    exit 1
fi
if [[ -L /proc/self/ns/user ]] && command -v unshare >/dev/null 2>&1 \
    && unshare --user true 2>/dev/null; then
    chmod 0755 "$sandbox"
else
    chmod 4755 "$sandbox"
fi

codec_dir=/opt/yandex/browser
if [[ -x "${codec_dir}/update_codecs" ]]; then
    rm -f -- "${codec_dir}/libffmpeg.so" "${codec_dir}/codecs_checksum"
    if ! "${codec_dir}/update_codecs" "$codec_dir"; then
        echo "Предупреждение: не удалось установить дополнительные медиакодеки." >&2
    fi
fi

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
