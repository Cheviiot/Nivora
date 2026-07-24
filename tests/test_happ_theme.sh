#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
launcher="${repo_root}/happ/happ-launcher"
staplerfile="${repo_root}/happ/Staplerfile"
tmp_dir="$(mktemp -d)"
trap 'rm -r -- "$tmp_dir"' EXIT

cp "$launcher" "${tmp_dir}/launcher-env"
sed -i 's|/opt/happ/bin/Happ|/usr/bin/env|' "${tmp_dir}/launcher-env"

default_env="$(env -u QT_QPA_PLATFORMTHEME "${tmp_dir}/launcher-env")"
grep -qx 'QT_QPA_PLATFORMTHEME=xdgdesktopportal' <<<"$default_env"

custom_env="$(QT_QPA_PLATFORMTHEME=qt6ct "${tmp_dir}/launcher-env")"
grep -qx 'QT_QPA_PLATFORMTHEME=qt6ct' <<<"$custom_env"

cp "$launcher" "${tmp_dir}/launcher-args"
sed -i 's|/opt/happ/bin/Happ|/usr/bin/printf|' "${tmp_dir}/launcher-args"
forwarded="$("${tmp_dir}/launcher-args" '%s:%s' first second)"
[[ "$forwarded" == 'first:second' ]]

grep -Fq "sed -i 's|^Exec=/opt/happ/bin/Happ|Exec=/usr/bin/happ|'" "$staplerfile"

echo 'OK: launcher Happ использует системную тему через XDG Desktop Portal'
