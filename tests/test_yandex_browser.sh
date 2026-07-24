#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
recipe="${repo_root}/yandex-browser-stable/Staplerfile"
postinstall="${repo_root}/yandex-browser-stable/postinstall.sh"

grep -Fq 'https://repo.yandex.ru/yandex-browser/deb/' "$recipe"
grep -Fq '/usr/bin/yandex-browser-stable' "$recipe"
grep -Fq 'extracted/usr/share/applications' "$recipe"
grep -Fq 'compatibility_desktop=' "$recipe"
grep -Fq 'canonical_desktop=' "$recipe"
grep -Fq "sed -i '/^NoDisplay=true\$/d'" "$recipe"
grep -Fq "sed -i '/^\\[Desktop Entry\\]\$/a NoDisplay=true'" "$recipe"
grep -Fq 'update_codecs' "$postinstall"

if grep -Eq '/etc/(cron|xdg/autostart)' "$recipe"; then
    echo 'Yandex Browser recipe must not package upstream auto-update hooks' >&2
    exit 1
fi

echo 'OK: Yandex Browser управляется Stapler без upstream cron-задач'
