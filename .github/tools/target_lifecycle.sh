#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"

readonly target_id="${TARGET_ID:?TARGET_ID is required}"
readonly package="${PACKAGE:?PACKAGE is required}"
readonly requested_stplr_path="${STPLR_PATH:?STPLR_PATH is required}"
readonly expected_arch="${EXPECTED_ARCH:?EXPECTED_ARCH is required}"
readonly os_release_path="${NIVORA_OS_RELEASE_PATH:-/etc/os-release}"
readonly test_root="${NIVORA_TEST_ROOT:-}"
readonly apparmor_userns_setting="${NIVORA_APPARMOR_USERNS_PATH:-/proc/sys/kernel/apparmor_restrict_unprivileged_userns}"
readonly stplr_cache_path="${NIVORA_STPLR_CACHE_PATH:-/var/cache/stplr}"

declare -Ar smoke_paths=(
    [anidesk]='/usr/bin/anidesk'
    [balena-etcher]='/usr/bin/balena-etcher'
    [chatgpt]='/usr/bin/chatgpt'
    [claude]='/usr/bin/claude-desktop'
    [distroshelf]='/usr/bin/distroshelf'
    [github-desktop]='/usr/bin/github-desktop'
    [nivora-cli]='/usr/bin/nv'
    [parsec]='/usr/bin/parsecd'
    [pineconemc]='/usr/bin/pineconemc'
    [telegram]='/usr/bin/telegram-desktop'
    [ventoy]='/usr/bin/ventoy'
    [vesktop]='/usr/bin/vesktop'
    [vintner]='/usr/bin/vintner'
    [yandex-music]='/usr/bin/yandex-music'
)

[[ "$target_id" == 'ubuntu-24.04' ]] || {
    echo "Unsupported target lifecycle: ${target_id}" >&2
    exit 2
}
[[ "$expected_arch" == 'amd64' || "$expected_arch" == 'arm64' ]] || {
    echo "Unsupported expected architecture: ${expected_arch}" >&2
    exit 2
}
[[ -v "smoke_paths[$package]" ]] || {
    echo "Package is not in the lifecycle allowlist: ${package}" >&2
    exit 2
}
[[ -f "${repo_root}/${package}/Staplerfile" ]] || {
    echo "Missing recipe: ${package}/Staplerfile" >&2
    exit 2
}
[[ -x "$requested_stplr_path" ]] || {
    echo "STPLR_PATH is not executable: ${requested_stplr_path}" >&2
    exit 2
}
[[ "${GITHUB_ACTIONS:-}" == 'true' || "${NIVORA_EPHEMERAL_TARGET:-0}" == '1' ]] || {
    echo 'Target lifecycle may run only in an explicitly ephemeral environment' >&2
    exit 2
}

if [[ -n "$test_root" ]]; then
    [[ "${NIVORA_TESTING:-0}" == '1' && "$test_root" == /* ]] || {
        echo 'NIVORA_TEST_ROOT is restricted to the test harness' >&2
        exit 2
    }
fi
if [[ "$os_release_path" != '/etc/os-release' ]]; then
    [[ "${NIVORA_TESTING:-0}" == '1' && "$os_release_path" == /* ]] || {
        echo 'NIVORA_OS_RELEASE_PATH is restricted to the test harness' >&2
        exit 2
    }
fi
if [[ "$apparmor_userns_setting" != '/proc/sys/kernel/apparmor_restrict_unprivileged_userns' ]]; then
    [[ "${NIVORA_TESTING:-0}" == '1' && "$apparmor_userns_setting" == /* ]] || {
        echo 'NIVORA_APPARMOR_USERNS_PATH is restricted to the test harness' >&2
        exit 2
    }
fi
if [[ "$stplr_cache_path" != '/var/cache/stplr' ]]; then
    [[ "${NIVORA_TESTING:-0}" == '1' && "$stplr_cache_path" == /* ]] || {
        echo 'NIVORA_STPLR_CACHE_PATH is restricted to the test harness' >&2
        exit 2
    }
fi

for command in apt-get bash cat chown cp dpkg-deb dpkg-query env find getent groupadd id install mktemp readlink rmdir runuser sysctl uname unshare useradd usermod; do
    command -v "$command" >/dev/null 2>&1 || {
        echo "Target lifecycle requires ${command}" >&2
        exit 2
    }
done

stplr_path="$(readlink -f -- "$requested_stplr_path")"
readonly stplr_path
[[ -x "$stplr_path" ]] || {
    echo "Unable to resolve STPLR_PATH: ${requested_stplr_path}" >&2
    exit 2
}
stplr_version="$("$stplr_path" version 2>&1)"
readonly stplr_version
[[ "$stplr_version" == 'v0.1.1' ]] || {
    echo "Target lifecycle requires Stapler v0.1.1, got: ${stplr_version}" >&2
    exit 2
}

[[ -r "$os_release_path" ]] || {
    echo "Cannot read ${os_release_path}" >&2
    exit 2
}
printf '%s\n' '==> target evidence: /etc/os-release'
cat -- "$os_release_path"
printf '%s\n' '==> target evidence: uname -a'
uname -a

ID=''
VERSION_ID=''
# shellcheck disable=SC1090
source "$os_release_path"
[[ "$ID" == 'ubuntu' && "$VERSION_ID" == '24.04' ]] || {
    echo "TARGET_ID ${target_id} requires Ubuntu 24.04; got ${ID:-unknown} ${VERSION_ID:-unknown}" >&2
    exit 2
}

case "$(uname -m)" in
x86_64 | amd64)
    readonly recipe_arch='amd64'
    readonly deb_arch='amd64'
    ;;
aarch64 | arm64)
    readonly recipe_arch='arm64'
    readonly deb_arch='arm64'
    ;;
*)
    echo "Unsupported native architecture: $(uname -m)" >&2
    exit 2
    ;;
esac
[[ "$recipe_arch" == "$expected_arch" ]] || {
    echo "Runner architecture ${recipe_arch} does not match EXPECTED_ARCH ${expected_arch}" >&2
    exit 2
}

elevate=()
if [[ "$EUID" -ne 0 ]]; then
    command -v sudo >/dev/null 2>&1 || {
        echo 'Passwordless sudo is required on the ephemeral target' >&2
        exit 2
    }
    sudo -n true
    elevate=(sudo -n --)
fi
runner_uid="$(id -u)"
runner_gid="$(id -g)"
readonly runner_uid runner_gid

temp_parent="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
[[ -d "$temp_parent" ]] || {
    echo "Temporary directory does not exist: ${temp_parent}" >&2
    exit 2
}
work_dir="$(mktemp -d -- "${temp_parent%/}/nivora-target-lifecycle.XXXXXX")"
stage="${work_dir}/package"
metadata_file="${work_dir}/recipe-metadata"
expected_system_name=''
apparmor_userns_original=''
apparmor_userns_changed=0

package_is_registered() {
    [[ -n "$expected_system_name" ]] &&
        dpkg-query -W -f='${binary:Package}\n' "$expected_system_name" \
            >/dev/null 2>&1
}

purge_package() {
    DEBIAN_FRONTEND=noninteractive "${elevate[@]}" apt-get purge -y \
        "$expected_system_name"
}

restore_apparmor_userns() {
    if [[ "$apparmor_userns_changed" -eq 1 ]]; then
        "${elevate[@]}" sysctl -q -w \
            "kernel.apparmor_restrict_unprivileged_userns=${apparmor_userns_original}"
        apparmor_userns_changed=0
    fi
}

cleanup() {
    local status=$?
    trap - EXIT
    if package_is_registered; then
        purge_package >/dev/null 2>&1 || true
    fi
    restore_apparmor_userns >/dev/null 2>&1 || true
    if [[ -d "$work_dir" ]]; then
        "${elevate[@]}" chown -R "${runner_uid}:${runner_gid}" "$work_dir" \
            >/dev/null 2>&1 || true
        find "$work_dir" -mindepth 1 -delete
        rmdir "$work_dir"
    fi
    return "$status"
}
trap cleanup EXIT

namespace_probe=(
    unshare --user --map-root-user --mount --pid --fork --uts --ipc --cgroup true
)
if ! "${namespace_probe[@]}"; then
    [[ -r "$apparmor_userns_setting" ]] || {
        echo 'Unprivileged build namespace is unavailable on this runner' >&2
        exit 2
    }
    apparmor_userns_original="$(
        sysctl -n kernel.apparmor_restrict_unprivileged_userns
    )"
    [[ "$apparmor_userns_original" =~ ^[0-9]+$ ]] || {
        echo 'Unable to read AppArmor user namespace policy' >&2
        exit 2
    }
    if [[ "$apparmor_userns_original" != '0' ]]; then
        "${elevate[@]}" sysctl -q -w \
            kernel.apparmor_restrict_unprivileged_userns=0
        apparmor_userns_changed=1
    fi
    "${namespace_probe[@]}" || {
        echo 'Unprivileged build namespace remains unavailable' >&2
        exit 2
    }
fi

install -d -- "$stage" "${work_dir}/home" "${work_dir}/cache"
cp -a -- "${repo_root}/${package}/." "$stage/"
find "$stage" -maxdepth 1 -type f \
    \( -name '*.deb' -o -name '*.rpm' -o -name '*.apk' -o -name '*.pkg.tar.*' \) \
    -delete

if ! bash --noprofile --norc -s -- "${stage}/Staplerfile" \
    >"$metadata_file" <<'METADATA'
set -euo pipefail
declare -A scripts=()
# shellcheck disable=SC1090
source "$1"
[[ -v name && -v version && -v release ]]
[[ "$(declare -p architectures 2>/dev/null)" == 'declare -a'* ]]
printf '%s\n' "$name" "$version" "$release" "${architectures[*]}"
METADATA
then
    echo "Unable to read recipe metadata for ${package}" >&2
    exit 1
fi

mapfile -t recipe_metadata <"$metadata_file"
[[ "${#recipe_metadata[@]}" -eq 4 ]] || {
    echo "Incomplete recipe metadata for ${package}" >&2
    exit 1
}
recipe_name="${recipe_metadata[0]}"
recipe_version="${recipe_metadata[1]}"
recipe_release="${recipe_metadata[2]}"
recipe_architectures="${recipe_metadata[3]}"

[[ "$recipe_name" =~ ^[a-z0-9][a-z0-9+.-]*$ && "$recipe_name" == "$package" ]] || {
    echo "Unexpected recipe name: ${recipe_name}" >&2
    exit 1
}
[[ "$recipe_version" =~ ^[A-Za-z0-9.+:~_-]+$ ]] || {
    echo "Unsafe recipe version: ${recipe_version}" >&2
    exit 1
}
[[ "$recipe_release" =~ ^[0-9]+$ ]] || {
    echo "Unsafe recipe release: ${recipe_release}" >&2
    exit 1
}
for declared_arch in $recipe_architectures; do
    [[ "$declared_arch" == 'all' || "$declared_arch" == 'amd64' || "$declared_arch" == 'arm64' ]] || {
        echo "Unknown recipe architecture: ${declared_arch}" >&2
        exit 1
    }
done
[[ " ${recipe_architectures} " == *" all "* ||
    " ${recipe_architectures} " == *" ${recipe_arch} "* ]] || {
    echo "Recipe ${package} does not support native ${recipe_arch}" >&2
    exit 1
}

expected_system_name="${recipe_name}+stplr-default"
if [[ " ${recipe_architectures} " == *' all '* ]]; then
    expected_artifact_arch='all'
else
    expected_artifact_arch="$deb_arch"
fi

if ! getent passwd stapler-builder >/dev/null; then
    "${elevate[@]}" useradd --system --user-group --create-home \
        --shell /usr/sbin/nologin stapler-builder
fi
if ! getent group wheel >/dev/null; then
    "${elevate[@]}" groupadd --system wheel
fi
"${elevate[@]}" usermod -a -G wheel stapler-builder
builder_entry="$(getent passwd stapler-builder)"
IFS=: read -r _ _ builder_uid builder_gid _ builder_home _ <<<"$builder_entry"
[[ "$builder_uid" =~ ^[0-9]+$ && "$builder_gid" =~ ^[0-9]+$ && "$builder_home" == /* ]] || {
    echo 'Invalid stapler-builder account' >&2
    exit 2
}
"${elevate[@]}" install -d -m0755 -o "$builder_uid" -g "$builder_gid" \
    "$stplr_cache_path"
chmod 0711 "$work_dir"
"${elevate[@]}" chown -R "${builder_uid}:${builder_gid}" \
    "$stage" "${work_dir}/home" "${work_dir}/cache"
if [[ "$EUID" -eq 0 ]]; then
    build_as_user=(runuser -u stapler-builder --)
else
    build_as_user=(sudo -n -- runuser -u stapler-builder --)
fi

printf '==> build %s for %s/%s with Stapler %s\n' \
    "$package" "$target_id" "$deb_arch" "$stplr_version"
(
    cd "$stage"
    "${build_as_user[@]}" env \
        HOME="${work_dir}/home" XDG_CACHE_HOME="${work_dir}/cache" \
        "$stplr_path" --interactive=false build --clean -s Staplerfile
)
restore_apparmor_userns

mapfile -d '' artifacts < <(
    find "$stage" -maxdepth 1 -type f -name '*.deb' -print0
)
[[ "${#artifacts[@]}" -eq 1 ]] || {
    echo "Expected exactly one DEB, found ${#artifacts[@]}" >&2
    exit 1
}
artifact="${artifacts[0]}"

actual_name="$(dpkg-deb -f "$artifact" Package)"
actual_version="$(dpkg-deb -f "$artifact" Version)"
actual_arch="$(dpkg-deb -f "$artifact" Architecture)"
[[ "$actual_name" == "$expected_system_name" ]] || {
    echo "DEB package mismatch: ${actual_name}; expected ${expected_system_name}" >&2
    exit 1
}
[[ "$actual_version" == "${recipe_version}-${recipe_release}" ]] || {
    echo "DEB version mismatch: ${actual_version}; expected ${recipe_version}-${recipe_release}" >&2
    exit 1
}
[[ "$actual_arch" == "$expected_artifact_arch" ]] || {
    echo "DEB architecture mismatch: ${actual_arch}; expected ${expected_artifact_arch}" >&2
    exit 1
}

smoke_path="${smoke_paths[$package]}"
rooted_smoke_path="${test_root}${smoke_path}"
package_is_registered && {
    echo "Refusing to replace pre-existing package ${expected_system_name}" >&2
    exit 1
}
[[ ! -e "$rooted_smoke_path" && ! -L "$rooted_smoke_path" ]] || {
    echo "Refusing to replace pre-existing path ${smoke_path}" >&2
    exit 1
}

DEBIAN_FRONTEND=noninteractive "${elevate[@]}" apt-get update
DEBIAN_FRONTEND=noninteractive "${elevate[@]}" apt-get install -y \
    --no-install-recommends "$artifact"
package_is_registered || {
    echo "Package was not registered after install: ${expected_system_name}" >&2
    exit 1
}
[[ -x "$rooted_smoke_path" ]] || {
    echo "Smoke path is missing or not executable: ${smoke_path}" >&2
    exit 1
}
if [[ "$package" == 'nivora-cli' ]]; then
    PATH="$(dirname "$stplr_path"):${PATH}" "$rooted_smoke_path" --version
fi

purge_package
if package_is_registered; then
    echo "Package remains registered after purge: ${expected_system_name}" >&2
    exit 1
fi
[[ ! -e "$rooted_smoke_path" && ! -L "$rooted_smoke_path" ]] || {
    echo "Smoke path remains after purge: ${smoke_path}" >&2
    exit 1
}

printf 'OK: %s lifecycle passed on %s/%s\n' "$package" "$target_id" "$deb_arch"
