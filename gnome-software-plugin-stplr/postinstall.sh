#!/bin/sh

if [ "${1:-}" = 1 ]; then
    printf '%s\n' 'Лицензия gnome-software-plugin-stplr — GPL-3.0-or-later. Подробности в /usr/share/licenses/gnome-software-plugin-stplr/' >&2 || :
fi
