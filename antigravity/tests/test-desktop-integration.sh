#!/bin/bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
desktop="${package_dir}/com.google.Antigravity.desktop"
staplerfile="${package_dir}/Staplerfile"

# OAuth returns antigravity://oauth-success; without this handler xdg-open
# shows "Нет доступных приложений".
grep -Eq '^MimeType=([^;]*;)?x-scheme-handler/antigravity(;|$)' "${desktop}"

# Chromium treats bare URLs as flags; -- keeps the deep link intact (telegram).
grep -Eq '^Exec=.+ -- %U$' "${desktop}"

# Wayland app_id is "antigravity". Ship antigravity.desktop for dock match,
# but MimeType must stay on ONLY that basename — two handlers force GNOME
# "Open With" every OAuth redirect and break silent token handoff.
grep -Fq 'antigravity.desktop' "${staplerfile}"
grep -Fq 'install-desktop com.google.Antigravity.desktop' "${staplerfile}"
grep -Fq "sed -e '/^MimeType=/d'" "${staplerfile}"
