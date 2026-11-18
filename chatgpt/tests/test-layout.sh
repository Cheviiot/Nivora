#!/bin/bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temp_dir="$(mktemp -d)"
cleanup() {
    find "$temp_dir" -mindepth 1 -delete
    rmdir "$temp_dir"
}
trap cleanup EXIT

# Stapler populates these variables and implements install-license in the builder.
# shellcheck disable=SC2034
declare -A scripts
# shellcheck disable=SC1091
source "${package_dir}/Staplerfile"
install-license() {
    install -Dm644 "$1" "${pkgdir}/usr/share/licenses/$2"
}

# shellcheck disable=SC2154
[[ "${provides[*]}" == codex && "${replaces[*]}" == 'chatgpt codex' && "${conflicts[*]}" == codex ]]
# shellcheck disable=SC2154
[[ "${sources[0]}" == *"chatgpt_amd64.deb?nivora=${source_fingerprint_amd64}&"* ]]
# shellcheck disable=SC2154
[[ "${sources_arm64[0]}" == *"chatgpt_arm64.deb?nivora=${source_fingerprint_arm64}&"* ]]

srcdir="${temp_dir}/src"
pkgdir="${temp_dir}/pkg"
deb_tree="${temp_dir}/debian"
app="${deb_tree}/usr/lib/chatgpt"
mkdir -p "$srcdir" "$pkgdir" "${deb_tree}/etc/apparmor.d" "${deb_tree}/usr/share/applications" \
    "${app}/node_modules/serialport-linux-x64-musl"
for path in ChatGPT codex-launcher browser_crashpad_handler LICENSES.chromium.html \
    libqt5_shim.so libqt6_shim.so node_modules/addon.musl.node \
    node_modules/serialport-linux-x64-musl/addon.node node_modules/addon.glibc.node; do
    touch "${app}/${path}"
done
printf 'profile chatgpt "/usr/lib/chatgpt/ChatGPT" { }\n' >"${deb_tree}/etc/apparmor.d/chatgpt"
printf '[Desktop Entry]\nExec=/vendor/chatgpt\n' >"${deb_tree}/usr/share/applications/chatgpt.desktop"
cp "${package_dir}/"{LICENSE,com.openai.chatgpt.png,com.openai.chatgpt.metainfo.xml} "$srcdir"
tar -czf "${temp_dir}/data.tar.gz" -C "$deb_tree" .
ar rc "${srcdir}/chatgpt.deb" "${temp_dir}/data.tar.gz"

# Simulate a second build sharing a source directory with a previous extraction.
mkdir -p "${srcdir}/extracted/usr/lib/chatgpt"
touch "${srcdir}/extracted/usr/lib/chatgpt/stale"
( package )

installed="${pkgdir}/usr/lib/chatgpt"
[[ "$(readlink "${pkgdir}/usr/bin/chatgpt")" == /usr/lib/chatgpt/ChatGPT ]]
for executable in ChatGPT codex-launcher browser_crashpad_handler; do
    [[ -x "${installed}/${executable}" ]]
done
[[ -f "${installed}/node_modules/addon.glibc.node" && ! -e "${installed}/stale" ]]
for path in libqt5_shim.so libqt6_shim.so node_modules/addon.musl.node node_modules/serialport-linux-x64-musl/addon.node; do
    [[ ! -e "${installed}/${path}" ]]
done
desktop="${pkgdir}/usr/share/applications/chatgpt.desktop"
grep -Fqx 'Exec=/usr/bin/chatgpt %U' "$desktop"
grep -Fqx 'StartupWMClass=Chatgpt' "$desktop"
cmp "${deb_tree}/etc/apparmor.d/chatgpt" "${pkgdir}/etc/apparmor.d/chatgpt"
cmp "${srcdir}/com.openai.chatgpt.metainfo.xml" "${pkgdir}/usr/share/metainfo/com.openai.chatgpt.metainfo.xml"
cmp "${srcdir}/LICENSE" "${pkgdir}/usr/share/licenses/chatgpt/LICENSE.nivora"

echo 'OK: ChatGPT stages the glibc payload, desktop launcher and matching AppArmor profile'
