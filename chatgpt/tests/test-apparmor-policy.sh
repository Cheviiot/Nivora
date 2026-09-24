#!/bin/bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
recipe="${package_dir}/Staplerfile"

grep -Fq "['preremove']='preremove.sh'" "$recipe"
grep -Fq "['postinstall']='postinstall.sh'" "$recipe"
# Stapler v0.1.1 ignores postupgrade on RPM and DEB, so declaring it would only
# look like upgrade coverage that does not exist. %post already runs on both.
if grep -Fq 'postupgrade' "$recipe"; then
    echo 'Stapler v0.1.1 ignores postupgrade on RPM/DEB; %post covers upgrades' >&2
    exit 1
fi
# The recipe must contain this literal shell code.
# shellcheck disable=SC2016
grep -Fq 'apparmor_parser -r -W -T "$profile"' \
    "${package_dir}/postinstall.sh"
# The hook must use its runtime profile variable.
# shellcheck disable=SC2016
grep -Fq 'apparmor_parser -R "$profile"' \
    "${package_dir}/preremove.sh"
grep -Fq '/usr/lib/chatgpt/ChatGPT' "$recipe"
bash "${package_dir}/preremove.sh" 1
bash "${package_dir}/preremove.sh" upgrade

echo 'OK: ChatGPT AppArmor profile lifecycle'
