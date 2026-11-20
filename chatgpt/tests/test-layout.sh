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
    "${app}/node_modules/serialport-linux-x64-musl" "${app}/resources"
for path in ChatGPT codex-launcher browser_crashpad_handler LICENSES.chromium.html \
    libqt5_shim.so libqt6_shim.so node_modules/addon.musl.node \
    node_modules/serialport-linux-x64-musl/addon.node node_modules/addon.glibc.node; do
    touch "${app}/${path}"
done
printf 'profile chatgpt "/usr/lib/chatgpt/ChatGPT" { }\n' >"${deb_tree}/etc/apparmor.d/chatgpt"
printf '[Desktop Entry]\nExec=/vendor/chatgpt\n' >"${deb_tree}/usr/share/applications/chatgpt.desktop"
cp "${package_dir}/"{LICENSE,com.openai.chatgpt.png,com.openai.chatgpt.metainfo.xml,patch-documents-dir.py} "$srcdir"
python3 - "${app}/resources/app.asar" <<'PY'
import hashlib
import json
import struct
import sys
from pathlib import Path

prefix = b"prefix"
resolver = (
    b'let settings="settings-store",key="projectlessWorkspaceRoot";'
    b'class Settings{getEffective(e){return this.get(e)??(0,i.crQ)(e).default}}'
)
suffix = b"suffix"
entry = {
    "offset": str(len(prefix)),
    "size": len(resolver),
    "integrity": {"algorithm": "SHA256", "blockSize": 128,
                  "hash": hashlib.sha256(resolver).hexdigest(),
                  "blocks": [hashlib.sha256(resolver).hexdigest()]},
}
header = json.dumps({"files": {
    "prefix": {"offset": "0", "size": len(prefix)},
    ".vite": {"files": {"build": {"files": {"early-bootstrap-1.js": entry}}}},
    "suffix": {"offset": str(len(prefix) + len(resolver)), "size": len(suffix)},
    "native.node": {"size": 1, "unpacked": True},
}}).encode()
padded_size = (len(header) + 3) & ~3
Path(sys.argv[1]).write_bytes(
    struct.pack("<IIII", 4, padded_size + 8, padded_size + 4, len(header))
    + header.ljust(padded_size, b"\0") + prefix + resolver + suffix
)
PY
tar -czf "${temp_dir}/data.tar.gz" -C "$deb_tree" .
write_deb() {
    printf 'Package: chatgpt\nVersion: %s\nArchitecture: %s\n' "$1" "$2" >"${temp_dir}/control"
    tar -czf "${temp_dir}/control.tar.gz" -C "$temp_dir" ./control
    ar rc "${srcdir}/chatgpt.deb" "${temp_dir}/control.tar.gz" "${temp_dir}/data.tar.gz"
}

ARCH=amd64
# shellcheck disable=SC2154
for fields in "${version} arm64" "0.0.1 amd64"; do
    read -r deb_version deb_arch <<<"$fields"
    write_deb "$deb_version" "$deb_arch"
    if ( package ) >"${temp_dir}/error" 2>&1; then
        echo "Accepted mismatched upstream DEB: ${fields}" >&2
        exit 1
    fi
    grep -Fq "Expected ChatGPT ${version} for ${ARCH}" "${temp_dir}/error"
    [[ ! -e "${pkgdir}/usr" ]]
done
write_deb "$version" "$ARCH"

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

python3 - "${installed}/resources/app.asar" <<'PY'
import hashlib
import json
import struct
import sys
from pathlib import Path

archive = Path(sys.argv[1]).read_bytes()
_, header_size, _, json_size = struct.unpack_from("<IIII", archive)
files = json.loads(archive[16:16 + json_size])["files"]

def content(entry):
    start = 8 + header_size + int(entry["offset"])
    return archive[start:start + entry["size"]]

assert content(files["prefix"]) == b"prefix"
assert content(files["suffix"]) == b"suffix"
assert files["native.node"] == {"size": 1, "unpacked": True}
entry = files[".vite"]["files"]["build"]["files"]["early-bootstrap-1.js"]
patched = content(entry)
assert b'this.get(e)??("linux"===process.platform&&"projectlessWorkspaceRoot"===e?' in patched
assert b'require("electron").app.getPath("documents"),"Codex"):(0,i.crQ)(e).default' in patched
integrity = entry["integrity"]
block_size = integrity["blockSize"]
assert integrity["hash"] == hashlib.sha256(patched).hexdigest()
assert integrity["blocks"] == [
    hashlib.sha256(patched[i:i + block_size]).hexdigest()
    for i in range(0, len(patched), block_size)
]
PY
echo 'OK: ChatGPT stages the glibc payload, XDG workspace default and matching AppArmor profile'
