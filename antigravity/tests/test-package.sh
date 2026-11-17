#!/bin/bash
# Stage the actual recipe body against small upstream-shaped archives. No
# vendor executable is run, and no files leave the temporary installation root.
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temp_dir="$(mktemp -d)"
cleanup() {
    find "$temp_dir" -mindepth 1 -delete
    rmdir "$temp_dir"
}
trap cleanup EXIT

# Unlike the shell fixtures below, this exercises the supported parser used
# by the updater. Bare local declarations and `local -a` once crashed its AST
# traversal despite package() itself running successfully in Bash.
if command -v stplr-spec >/dev/null 2>&1; then
    parser_recipe="${temp_dir}/Staplerfile.parser"
    cp "${package_dir}/Staplerfile" "$parser_recipe"
    stplr-spec set-field --path "$parser_recipe" version 9.8.7
    stplr-spec set-field --path "$parser_recipe" upstream_hub 9.8.7-12345
    stplr-spec set-field --path "$parser_recipe" release 1
    [[ "$(stplr-spec get-field --path "$parser_recipe" version)" == 9.8.7 ]]
    [[ "$(stplr-spec get-field --path "$parser_recipe" upstream_hub)" == 9.8.7-12345 ]]
    [[ "$(stplr-spec get-field --path "$parser_recipe" release)" == 1 ]]
    python3 - "${package_dir}/Staplerfile" "$parser_recipe" <<'PY'
import re
import sys
from pathlib import Path

def unchanged_fields(path):
    text = Path(path).read_text(encoding="utf-8")
    for field in ("version", "upstream_hub", "release"):
        text, count = re.subn(rf"^{field}=.*$", f"{field}=VALUE", text, flags=re.M)
        assert count == 1, (field, count)
    return text

assert unchanged_fields(sys.argv[1]) == unchanged_fields(sys.argv[2]), "set-field changed unrelated recipe content"
PY
fi

make_fixture() {
    python3 - "$@" <<'PY'
import io
import json
import struct
import sys
import tarfile
from pathlib import Path

directory, architecture, scenario, version = sys.argv[1:]
root = "Antigravity-x64" if architecture == "amd64" else "Antigravity-arm64"
machine = 62 if architecture == "amd64" else 183
if scenario == "wrong-machine":
    machine = 183 if machine == 62 else 62

elf = bytearray(64)
elf[:7] = b"\x7fELF\x02\x01\x01"
struct.pack_into("<HHI", elf, 16, 3, machine, 1)

manifest = {
    "name": "antigravity",
    "productName": "Antigravity",
    "version": "0.0.0" if scenario == "wrong-version" else version,
    "main": "dist/main.js",
}
if scenario == "wrong-name":
    manifest["name"] = "other-application"
if scenario == "wrong-product-name":
    manifest["productName"] = "OtherApplication"
if scenario == "missing-product-name":
    del manifest["productName"]
if scenario == "wrong-desktop-name":
    manifest["desktopName"] = "other.desktop"

members = {
    "package.json": json.dumps(manifest).encode(),
    "dist/main.js": b"// fixture entry point\n",
    # A whole-ASAR grep would wrongly accept this version when the root
    # package.json above says 0.0.0.
    "node_modules/dependency/package.json": json.dumps({"version": version}).encode(),
}
if scenario == "missing-main":
    del members["dist/main.js"]

header = {"files": {}}
content = bytearray()
for path, data in members.items():
    node = header["files"]
    *parents, filename = path.split("/")
    for parent in parents:
        node = node.setdefault(parent, {"files": {}})["files"]
    node[filename] = {"offset": str(len(content)), "size": len(data)}
    content.extend(data)
encoded_header = json.dumps(header, separators=(",", ":")).encode()
padding = b"\0" * (-len(encoded_header) % 4)
header_pickle = (
    struct.pack("<II", 4 + len(encoded_header) + len(padding), len(encoded_header))
    + encoded_header + padding
)
asar = struct.pack("<II", 4, len(header_pickle)) + header_pickle + content
if scenario == "broken-asar":
    asar = b"not an ASAR archive"

files = {
    "antigravity": (bytes(elf), 0o755),
    "chrome-sandbox": (bytes(elf), 0o755),
    "LICENSES.chromium.html": (b"Chromium fixture license\n", 0o644),
    "LICENSE.electron.txt": (b"Electron fixture license\n", 0o644),
    "resources/app.asar": (asar, 0o644),
    "resources/app-update.yml": (b"provider: generic\n", 0o644),
}
if scenario == "wrong-sandbox-machine":
    sandbox_elf = bytearray(elf)
    struct.pack_into("<H", sandbox_elf, 18, 183 if machine == 62 else 62)
    files["chrome-sandbox"] = (bytes(sandbox_elf), 0o755)
if scenario == "missing-sandbox":
    del files["chrome-sandbox"]
roots = [root]
if scenario == "ambiguous-roots":
    roots = ["Antigravity-x64", "Antigravity-arm64"]
with tarfile.open(Path(directory) / "Antigravity.tar.gz", "w:gz") as archive:
    for payload_root in roots:
        for name, (data, mode) in files.items():
            member = tarfile.TarInfo(f"{payload_root}/{name}")
            member.size = len(data)
            member.mode = mode
            archive.addfile(member, io.BytesIO(data))
PY
}

# These helpers reproduce Stapler's installation destinations and recursive
# file discovery, retaining repeated paths so manifest collisions stay visible.
install-desktop() {
    install -Dm644 "$1" "${pkgdir}/usr/share/applications/$(basename "$1")"
}

install-license() {
    install -Dm644 "$1" "${pkgdir}/usr/share/licenses/$2"
}

files-find() {
    python3 - "$pkgdir" "$@" <<'PY'
import glob
import os
import sys

root, *patterns = sys.argv[1:]
for pattern in patterns:
    for path in sorted(glob.glob(root + pattern, recursive=True)):
        if os.path.isfile(path) or os.path.islink(path):
            print(path[len(root):])
PY
}

files-find-binary() { files-find '/usr/bin/*'; }
files-find-desktop() { files-find '/usr/share/applications/*.desktop'; }
files-find-license() { files-find '/usr/share/licenses/**/*'; }

stage() (
    set -euo pipefail
    local scenario="$1" architecture="$2" source path
    # The sourced recipe assigns lifecycle hooks using associative indices.
    # shellcheck disable=SC2034
    declare -A scripts
    # shellcheck disable=SC1091
    source "${package_dir}/Staplerfile"
    # These variables are consumed by the sourced recipe bodies and helpers.
    # shellcheck disable=SC2034
    srcdir="${temp_dir}/${scenario}-${architecture}/src"
    pkgdir="${temp_dir}/${scenario}-${architecture}/pkg"
    mkdir -p "$srcdir" "$pkgdir"
    # Source arrays are supplied by the real recipe loaded above.
    # shellcheck disable=SC2154
    local -a fixture_sources=("${sources[@]}")
    if [[ "$architecture" == arm64 ]]; then
        # shellcheck disable=SC2154
        fixture_sources=("${sources_arm64[@]}")
    fi
    for source in "${fixture_sources[@]}"; do
        [[ "$source" == local:///* ]] || continue
        path="${source#local:///}"
        path="${path%%\?*}"
        cp "${package_dir}/${path}" "${srcdir}/${path}"
    done
    # version is another public recipe field, not a fixture constant.
    # shellcheck disable=SC2154
    make_fixture "$srcdir" "$architecture" "$scenario" "$version"
    # A stale x64 extraction must never override an ARM archive on rebuild.
    if [[ "$architecture" == arm64 ]]; then
        mkdir -p "${srcdir}/Antigravity-x64"
        printf '%s\n' stale >"${srcdir}/Antigravity-x64/stale-marker"
    fi
    if [[ "$scenario" == wrong-hub ]]; then
        # package() reads this recipe field when validating its build pin.
        # shellcheck disable=SC2034
        upstream_hub='0.0.0-1234'
    fi
    # Stapler v0.1.1 decoder.runFunc executes the stored function body directly
    # with sub.Run(ctx, fn), without a function call frame. Calling package()
    # here hid `local` declarations that fail in the real ALT build. Strip only
    # Bash's normalized function envelope, then run its body at top level in a
    # separate shell; sourcing preserves the recipe's explicit return handling.
    local package_body="${temp_dir}/${scenario}-${architecture}/package-body.sh"
    declare -f package | sed '1,2d;$d' >"$package_body"
    export -f install-desktop install-license
    bash -euo pipefail -c '
        declare -A scripts
        # shellcheck disable=SC1090
        source "$1"
        srcdir=$2
        pkgdir=$3
        upstream_hub=$4
        # This source is deliberately outside every shell function.
        # shellcheck disable=SC1090
        source "$5"
    ' antigravity-package-body "${package_dir}/Staplerfile" \
        "$srcdir" "$pkgdir" "$upstream_hub" "$package_body"
    files >"${temp_dir}/${scenario}-${architecture}/manifest"
)

for architecture in amd64 arm64; do
    set +e
    stage valid "$architecture" >"${temp_dir}/valid-${architecture}.log" 2>&1
    status=$?
    set -e
    if [[ "$status" -ne 0 ]]; then
        cat "${temp_dir}/valid-${architecture}.log" >&2
        exit 1
    fi
    python3 - "${temp_dir}/valid-${architecture}" <<'PY'
import configparser
import stat
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

work = Path(sys.argv[1])
root = work / "pkg"
launchers = list((root / "usr/share/applications").glob("*.desktop"))
assert [path.name for path in launchers] == ["antigravity.desktop"], launchers
desktop = configparser.ConfigParser(interpolation=None)
desktop.read(launchers[0], encoding="utf-8")
entry = desktop["Desktop Entry"]
assert entry["Type"] == "Application", dict(entry)
assert not entry.getboolean("Hidden", fallback=False), dict(entry)
assert not entry.getboolean("NoDisplay", fallback=False), dict(entry)
assert entry["Exec"] == "/usr/bin/antigravity -- %U", dict(entry)
assert entry["MimeType"].split(";").count("x-scheme-handler/antigravity") == 1, dict(entry)
assert entry["Icon"] == "com.google.Antigravity", dict(entry)
assert entry["StartupWMClass"] == "antigravity", dict(entry)
assert (root / "usr/share/icons/hicolor/256x256/apps/com.google.Antigravity.png").is_file()
metadata = ET.parse(root / "usr/share/metainfo/com.google.Antigravity.metainfo.xml").getroot()
assert metadata.findtext("id") == "com.google.Antigravity"
assert metadata.findtext("launchable[@type='desktop-id']") == "antigravity.desktop"
launcher = root / "usr/bin/antigravity"
assert launcher.is_file() and not launcher.is_symlink(), launcher
assert launcher.stat().st_mode & stat.S_IXUSR, launcher
sandbox = root / "opt/antigravity/chrome-sandbox"
assert stat.S_IMODE(sandbox.stat().st_mode) == 0o4755, oct(sandbox.stat().st_mode)
assert stat.S_IMODE((root / "opt/antigravity/antigravity").stat().st_mode) == 0o755
assert not (root / "opt/antigravity/resources/app-update.yml").exists()
assert not (root / "opt/antigravity/stale-marker").exists()
for license_name in ("LICENSE.nivora", "LICENSES.chromium.html", "LICENSE.electron.txt"):
    assert (root / "usr/share/licenses/antigravity" / license_name).is_file(), license_name
manifest = (work / "manifest").read_text(encoding="utf-8").splitlines()
assert len(manifest) == len(set(manifest)), "duplicate paths in files() output"
assert "/usr/share/applications/antigravity.desktop" in manifest
actual_files = {
    "/" + str(path.relative_to(root))
    for path in root.rglob("*") if path.is_file() or path.is_symlink()
}
assert set(manifest) == actual_files, (actual_files - set(manifest), set(manifest) - actual_files)
PY
done

for scenario in wrong-hub wrong-version wrong-name wrong-product-name missing-product-name \
    wrong-desktop-name missing-main wrong-machine wrong-sandbox-machine \
    ambiguous-roots missing-sandbox broken-asar; do
    # Running a function in an `if` suppresses errexit for its whole body;
    # let the subshell's own errexit propagate the first rejected payload.
    set +e
    stage "$scenario" amd64 >"${temp_dir}/${scenario}.log" 2>&1
    status=$?
    set -e
    if [[ "$status" -eq 0 ]]; then
        echo "Antigravity unexpectedly accepted ${scenario}" >&2
        exit 1
    fi
done

echo 'OK: Antigravity stages both architectures and rejects invalid upstream payloads'
