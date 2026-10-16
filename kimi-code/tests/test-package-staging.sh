#!/bin/bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -r -- "$fixture"' EXIT
srcdir="$fixture/src"
pkgdir="$fixture/pkg"
export srcdir pkgdir
mkdir -p "$srcdir" "$pkgdir"

# A minimal upstream DEB exercises package(), including absolute links,
# without requiring the application to be installed on the build host.
payload="$fixture/payload"
app="$payload/opt/Kimi Code"
mkdir -p "$app/resources" "$payload/usr/share/applications" \
    "$payload/usr/share/icons/hicolor/512x512/apps" "$payload/usr/share/metainfo"
for file in kimi-code chrome-sandbox chrome_crashpad_handler \
    LICENSE.electron.txt LICENSES.chromium.html; do
    printf 'fixture\n' > "$app/$file"
done
printf '"/opt/Kimi Code/kimi-code"\n' > "$app/resources/apparmor-profile"
printf '[Desktop Entry]\nName=Kimi Code\nExec="/opt/Kimi Code/kimi-code"\n' \
    > "$payload/usr/share/applications/kimi-code.desktop"
printf '<component/>\n' \
    > "$payload/usr/share/metainfo/com.kimi.code.desktop.metainfo.xml"
tar -czf "$fixture/data.tar.gz" -C "$payload" .
(cd "$fixture" && ar rc "$srcdir/kimi-code.deb" data.tar.gz)
cp "$package_dir/LICENSE" "$srcdir/LICENSE"

# Stapler helpers are replaced only at their file-install boundary.
install-desktop() {
    install -Dm644 "$1" "$pkgdir/usr/share/applications/$(basename "$1")"
}
install-license() {
    install -Dm644 "$1" "$pkgdir/usr/share/licenses/$2"
}
# shellcheck disable=SC2034
declare -A scripts
# shellcheck disable=SC1091
source "$package_dir/Staplerfile"
package

test -f "$pkgdir/opt/Kimi Code/kimi-code"
test -L "$pkgdir/usr/bin/kimi-code"
test "$(readlink "$pkgdir/usr/bin/kimi-code")" = '/opt/Kimi Code/kimi-code'
test -f "$pkgdir/usr/share/applications/kimi-code.desktop"
test -f "$pkgdir/usr/share/metainfo/com.kimi.code.desktop.metainfo.xml"
test "$(stat -c '%a' "$pkgdir/opt/Kimi Code/chrome-sandbox")" = 4755
