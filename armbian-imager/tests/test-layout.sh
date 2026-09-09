#!/bin/bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
recipe="${package_dir}/Staplerfile"

grep -Fq "architectures=('amd64' 'arm64')" "$recipe"
# shellcheck disable=SC2016
grep -Fq 'Armbian.Imager_${version}_amd64.deb' "$recipe"
# shellcheck disable=SC2016
grep -Fq 'Armbian.Imager_${version}_arm64.deb' "$recipe"
grep -Fq '/usr/share/applications/armbian-imager.desktop' "$recipe"
grep -Fq "deps_altlinux=('udisks2' 'util-linux' 'xdg-utils')" "$recipe"
grep -Fq "'libwebkit2gtk-4_1-0' 'libgtk-3-0'" "$recipe"
grep -Fq "incompatible_with=('alpine')" "$recipe"

if grep -Fq '.AppImage' "$recipe"; then
    echo 'Armbian Imager must be packaged from official DEBs, not AppImage' >&2
    exit 1
fi
if grep -Eq 'systemctl[[:space:]].*(enable|start)|udisksctl[[:space:]].*(mount|power-off)' \
    "${package_dir}"/post*.sh; then
    echo 'Lifecycle hooks must not start services or touch storage devices' >&2
    exit 1
fi
