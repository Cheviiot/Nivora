#!/bin/bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wrapper="${package_dir}/github-desktop-git-wrapper"
recipe="${package_dir}/Staplerfile"
work_dir="$(mktemp -d)"
cleanup() {
    find "$work_dir" -mindepth 1 -delete
    rmdir "$work_dir"
}
trap cleanup EXIT

install -m755 "$wrapper" "${work_dir}/git-remote-http"
cat >"${work_dir}/git-remote-http.bin" <<'EOF'
#!/bin/sh
printf '%s\n' "$*"
EOF
chmod 0755 "${work_dir}/git-remote-http.bin"
for alias in git-remote-https git-remote-ftp git-remote-ftps; do
    ln -s git-remote-http "${work_dir}/${alias}"
done

[[ "$("${work_dir}/git-remote-http" one two)" == 'one two' ]]
for alias in git-remote-https git-remote-ftp git-remote-ftps; do
    [[ "$("${work_dir}/${alias}" secure)" == 'secure' ]]
done
[[ "$(PATH="${work_dir}:$PATH" git-remote-http three)" == 'three' ]]
grep -Fq "'libcurl4-openssl'" "$recipe"
grep -Fq 'local:///github-desktop-git-wrapper' "$recipe"
grep -Fq '/usr/lib64/libcurl4-openssl' "$wrapper"

echo 'OK: GitHub Desktop portable Git curl ABI wrapper'
