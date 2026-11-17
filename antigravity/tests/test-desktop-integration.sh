#!/bin/bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
desktop="${package_dir}/com.google.Antigravity.desktop"
staplerfile="${package_dir}/Staplerfile"

# OAuth returns antigravity://oauth-success; without this handler xdg-open
# shows "Нет доступных приложений".
grep -Eq '^MimeType=([^;]*;)?x-scheme-handler/antigravity(;|$)' "${desktop}"

# Wayland app_id is "antigravity" (dock tooltip). GNOME looks for
# antigravity.desktop; AppStream keeps com.google.Antigravity.desktop.
grep -Fq 'antigravity.desktop' "${staplerfile}"
grep -Fq 'install-desktop com.google.Antigravity.desktop' "${staplerfile}"
