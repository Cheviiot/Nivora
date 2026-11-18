#!/bin/bash
# Exercise the real package() against a portable archive whose metadata still
# belongs to Prism Launcher. No network or system installation is involved.
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -r -- "$fixture"' EXIT
archive_root="${fixture}/archive"
srcdir="${fixture}/source"
pkgdir="${fixture}/package"
component_id='io.github.elyprismlauncher.ElyPrismLauncher'
metainfo_name="${component_id}.metainfo.xml"
mkdir -p "${archive_root}/bin" \
    "${archive_root}/share/applications" \
    "${archive_root}/share/metainfo" \
    "${archive_root}/share/mime/packages" \
    "${archive_root}/share/man/man6" \
    "${archive_root}/share/icons/hicolor/scalable/apps" "$srcdir" "$pkgdir"

printf '#!/bin/sh\nexit 0\n' >"${archive_root}/bin/elyprismlauncher"
touch "${archive_root}/bin/elyprismlauncher_updater" "${archive_root}/portable.txt"
cat >"${archive_root}/share/applications/${component_id}.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=PineconeMC
Exec=elyprismlauncher
Icon=io.github.elyprismlauncher.ElyPrismLauncher
Categories=Utility;
EOF
cat >"${archive_root}/share/metainfo/${metainfo_name}" <<'EOF'
<component type="desktop-application">
  <id>io.github.elyprismlauncher.ElyPrismLauncher</id>
  <name>Prism Launcher</name>
  <description><p>Prism Launcher is a custom launcher for Minecraft.</p></description>
  <developer id="org.prismlauncher"><name>Prism Launcher Contributors</name></developer>
  <url type="homepage">https://prismlauncher.org/</url>
  <url type="bugtracker">https://github.com/PrismLauncher/PrismLauncher/issues</url>
  <url type="donation">https://opencollective.com/prismlauncher</url>
</component>
EOF
printf '<mime-info/>\n' >"${archive_root}/share/mime/packages/${component_id}.xml"
printf 'PineconeMC fixture\n' >"${archive_root}/share/man/man6/elyprismlauncher.6"
cp "${package_dir}/${component_id}.svg" \
    "${archive_root}/share/icons/hicolor/scalable/apps/${component_id}.svg"
tar -czf "${srcdir}/pineconemc.tar.gz" -C "$archive_root" .
cp "${package_dir}/LICENSE" "${package_dir}/${metainfo_name}" "$srcdir/"

# Stapler's keyed script metadata must remain associative when sourced by Bash.
# shellcheck disable=SC2034
declare -A scripts
# shellcheck disable=SC1091
source "${package_dir}/Staplerfile"

check_metadata_source() {
    local -n declared_sources="$1"
    local -n declared_checksums="$2"
    local index matches=0 expected_checksum
    expected_checksum="sha256:$(sha256sum "${srcdir}/${metainfo_name}" | cut -d ' ' -f1)"
    [[ "${#declared_sources[@]}" == "${#declared_checksums[@]}" ]]
    for index in "${!declared_sources[@]}"; do
        if [[ "${declared_sources[index]}" == "local:///${metainfo_name}"* ]]; then
            [[ "${declared_checksums[index]}" == "$expected_checksum" ]]
            matches=$((matches + 1))
        fi
    done
    [[ "$matches" == 1 ]]
}
check_metadata_source sources checksums
check_metadata_source sources_arm64 checksums_arm64

install-license() {
    install -Dm644 "$1" "${pkgdir}/usr/share/licenses/$2"
}
package

python3 - "$package_dir" "$pkgdir" <<'PY'
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import urlsplit

package_dir, payload = map(Path, sys.argv[1:])
component_id = "io.github.elyprismlauncher.ElyPrismLauncher"
metadata_name = f"{component_id}.metainfo.xml"
canonical = package_dir / metadata_name
installed = payload / "usr/share/metainfo" / metadata_name
assert installed.read_bytes() == canonical.read_bytes(), "installed metadata differs from the catalog"
assert not (payload / "opt/pineconemc/share/metainfo" / metadata_name).exists(), "inherited Prism metadata remains in /opt"
document = ET.parse(installed).getroot()
assert document.findtext("id") == component_id
assert document.findtext("name") == "PineconeMC"
developer = document.find("developer")
assert developer is not None
assert developer.get("id") == "io.github.elyprismlauncher"
assert developer.findtext("name") == "ElyPrismLauncher"
assert document.findtext("url[@type='homepage']") == "https://elyprismlauncher.github.io/"
assert document.findtext("categories/category") == "Game"
assert document.findtext("launchable[@type='desktop-id']") == f"{component_id}.desktop"
assert document.find("content_rating") is None, "unverified age rating must stay unknown"
for node in document.findall(".//url") + document.findall(".//image"):
    url = urlsplit(node.text or "")
    assert url.scheme == "https"
    assert "prismlauncher.org" not in (url.hostname or "")
    assert "/PrismLauncher/" not in url.path
    assert "/prismlauncher" not in url.path.lower(), "inherited Prism service link"
assert all("Prism Launcher" not in (node.text or "") for node in document.findall(".//name"))
image = document.find("screenshots/screenshot[@type='default']/image[@type='source']")
assert image is not None
assert image.text == "https://raw.githubusercontent.com/ElyPrismLauncher/elyprismlauncher.github.io/6f848e647bd36351b71095575cd01f127789697e/assets/png/screenshot.png"
assert (image.get("width"), image.get("height")) == ("960", "640")
desktop = (payload / "usr/share/applications" / f"{component_id}.desktop").read_text()
assert "Categories=Game;\n" in desktop
assert (payload / "usr/share/icons/hicolor/scalable/apps" / f"{component_id}.svg").is_file()
PY

echo 'OK: PineconeMC metadata sources cover both architectures and replace inherited Prism identity'
