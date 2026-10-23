#!/bin/bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
staplerfile="${package_dir}/Staplerfile"

# The recipe must contain this literal shell code.
# shellcheck disable=SC2016
grep -Fq 'install -Dm755 "${srcdir}/extracted/usr/bin/unsloth-studio"' "$staplerfile"
grep -Fq "usr/share/applications/unsloth.desktop" "$staplerfile"
grep -Fq 'Categories=Development' "$staplerfile"
grep -Fq 'ai.unsloth.studio.update.policy' "$staplerfile"
# /usr/share must exist in pkgdir before cp -a drops icons into it; without
# the mkdir cp silently turns the icons tree into usr/share/hicolor and
# files() then fails with "glob pattern error: pattern does not exist".
# shellcheck disable=SC2016
grep -Fq 'install -dm755 "${pkgdir}/usr/share"' "$staplerfile"
grep -Fq 'appstream_app_id='"'"'unsloth'"'"'' "$staplerfile"
grep -Fq 'provides=()' "$staplerfile"
grep -Fq 'replaces=('"'"'unsloth'"'"')' "$staplerfile"
grep -Fq 'conflicts=()' "$staplerfile"
# The upstream DEB transitions unsloth-studio-desktop; the recipe must not
# carry those names in provides/conflicts (validator keeps them empty).
if grep -Eq 'provides=\('"'"'unsloth-studio-desktop|conflicts=\('"'"'unsloth-studio-desktop' "$staplerfile"; then
    exit 1
fi
if grep -Fq 'chrome-sandbox' "$staplerfile"; then
    # Tauri/WebKit app: no Electron setuid sandbox helper exists.
    exit 1
fi
if grep -Fq 'postupgrade' "$staplerfile"; then
    # Stapler v0.1.1 ignores postupgrade on RPM/DEB; %post covers upgrades.
    exit 1
fi
