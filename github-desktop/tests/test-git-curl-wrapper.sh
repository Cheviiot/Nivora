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
for alias in git-remote-https git-remote-ftp git-remote-ftps; do
    ln -s git-remote-http "${work_dir}/${alias}"
done

system_exec_path="$(/usr/bin/git --exec-path)"
for helper in git-http-fetch git-http-push git-imap-send git-remote-http; do
    [[ -x "${system_exec_path}/${helper}" ]]
done

for helper in git-remote-http git-remote-https git-remote-ftp git-remote-ftps; do
    set +e
    output="$(GIT_EXEC_PATH=/definitely/not/system \
        "${work_dir}/${helper}" 2>&1)"
    status=$?
    set -e
    [[ "$status" -eq 1 ]]
    grep -Fq 'usage: git remote-curl' <<<"$output"
    if grep -Fq 'CURL_OPENSSL_4' <<<"$output"; then
        exit 1
    fi
done

if grep -Fq "'libcurl4-openssl'" "$recipe"; then
    exit 1
fi
grep -Fq 'local:///github-desktop-git-wrapper' "$recipe"
grep -Fq '/usr/bin/git --exec-path' "$wrapper"
grep -Fq 'unset GIT_EXEC_PATH' "$wrapper"
# These patterns intentionally contain literal package-script variables.
# shellcheck disable=SC2016
recipe_remove_pattern='rm -f "${git_core}/${helper}"'
# shellcheck disable=SC2016
wrapper_bin_pattern='${helper}.bin'
grep -Fq "$recipe_remove_pattern" "$recipe"
if grep -Fq "$wrapper_bin_pattern" "$wrapper"; then
    exit 1
fi

echo 'OK: GitHub Desktop portable Git uses distro-native network helpers'
