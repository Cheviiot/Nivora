#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
package_dir="${repo_root}/ventoy"
launcher="${package_dir}/ventoy"
desktop="${package_dir}/ventoy.desktop"
recipe="${package_dir}/Staplerfile"
temp_dir="$(mktemp -d)"

cleanup() {
    find "$temp_dir" -mindepth 1 -delete
    rmdir "$temp_dir"
}
trap cleanup EXIT

case "$(uname -m)" in
x86_64 | amd64)
    gui='VentoyGUI.x86_64'
    ;;
aarch64 | arm64)
    gui='VentoyGUI.aarch64'
    ;;
*)
    echo 'SKIP: архитектура не поддерживается тестом Ventoy'
    exit 0
    ;;
esac

cat >"${temp_dir}/${gui}" <<'EOF'
#!/bin/bash
set -euo pipefail
printf 'cwd=%s\n' "$PWD" >"$NIVORA_TEST_LOG"
printf 'arg=%s\n' "$@" >>"$NIVORA_TEST_LOG"
EOF
chmod 0755 "${temp_dir}/${gui}"

export VENTOY_INSTALL_DIR="$temp_dir"
export NIVORA_TEST_LOG="${temp_dir}/launch.log"
"$launcher" --qt5

grep -Fxq "cwd=${temp_dir}" "$NIVORA_TEST_LOG"
grep -Fxq 'arg=--qt5' "$NIVORA_TEST_LOG"
grep -Fxq 'Name=Ventoy' "$desktop"
grep -Fxq 'Exec=ventoy' "$desktop"
grep -Fxq 'Icon=ventoy' "$desktop"
grep -Fq "architectures=('amd64' 'arm64')" "$recipe"
grep -Fq "VentoyGUI.\${candidate}" "$recipe"
grep -Fq "case \"\$(uname -m)\" in" "$recipe"

echo 'OK: Ventoy launcher'
