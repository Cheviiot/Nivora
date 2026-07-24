#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
# shellcheck source=tools/lib/source_cache.sh
source "${script_dir}/lib/source_cache.sh"
cd "$repo_root"

mapfile -t all_packages < <(
    for staplerfile in */Staplerfile; do
        dirname "$staplerfile"
    done | sort
)

is_package() {
    local requested="$1"
    local package
    for package in "${all_packages[@]}"; do
        [[ "$requested" == "$package" ]] && return 0
    done
    return 1
}

packages=()
if [[ "${1:-}" == '--all' ]]; then
    packages=("${all_packages[@]}")
    shift
else
    packages=("$@")
fi

[[ "${#packages[@]}" -gt 0 ]] || {
    echo 'Usage: tools/clean_build.sh {--all|package...}' >&2
    exit 2
}

for package in "${packages[@]}"; do
    is_package "$package" || {
        echo "Unknown package: ${package}" >&2
        exit 2
    }
done

if command -v podman >/dev/null 2>&1; then
    engine=podman
elif command -v docker >/dev/null 2>&1; then
    engine=docker
else
    echo 'clean-build requires stplr-spec with clean-build, Podman or Docker' >&2
    exit 2
fi

readonly image='registry.altlinux.org/sisyphus/base:latest'
readonly cache_volume="nivora-clean-build-cache-$$"
readonly builder_image="nivora-clean-build:$$"
builder_dir="$(mktemp -d)"
docker_config=''
source_cache="${NIVORA_SOURCE_CACHE:-${XDG_CACHE_HOME:-${HOME}/.cache}/stplr/dl}"

cleanup() {
    "$engine" volume rm "$cache_volume" >/dev/null 2>&1 || true
    "$engine" image rm "$builder_image" >/dev/null 2>&1 || true
    find "$builder_dir" -mindepth 1 -delete
    rmdir "$builder_dir"
    if [[ -n "$docker_config" ]]; then
        find "$docker_config" -mindepth 1 -delete
        rmdir "$docker_config"
    fi
}
trap cleanup EXIT

if [[ "$engine" == docker ]]; then
    docker_config="$(mktemp -d)"
    printf '{}\n' >"${docker_config}/config.json"
    export DOCKER_CONFIG="$docker_config"
fi

cat >"${builder_dir}/Containerfile" <<EOF
FROM ${image}
RUN for attempt in 1 2 3; do \
        apt-get update \
        && apt-get dist-upgrade -y \
        && apt-get install -y ca-certificates stplr binutils python3 \
        && exit 0; \
        sleep 5; \
    done; \
    exit 1
EOF

pulled=0
for attempt in 1 2 3; do
    if "$engine" pull "$image"; then
        pulled=1
        break
    fi
    sleep "$((attempt * 5))"
done
[[ "$pulled" -eq 1 ]] || exit 1
"$engine" volume create "$cache_volume" >/dev/null
"$engine" build -t "$builder_image" -f "${builder_dir}/Containerfile" "$builder_dir"

import_stplr_source_cache \
    "$engine" "$builder_image" "$cache_volume" "$builder_dir" "$source_cache" \
    "${packages[@]}"

for package in "${packages[@]}"; do
    echo "==> clean-build ${package} (${engine})"
    find "$package" -maxdepth 1 -type f \
        \( -name '*.rpm' -o -name '*.deb' -o -name '*.apk' -o -name '*.pkg.tar.*' \) \
        -delete
    built=0
    for attempt in 1 2; do
        if "$engine" run --rm --privileged \
            -e TERM=xterm-256color \
            -v "${repo_root}/${package}:/app" \
            -v "${cache_volume}:/var/cache/stplr" \
            -w /app \
            "$builder_image" \
            stplr --interactive=false build --clean -s Staplerfile; then
            built=1
            break
        fi
        echo "==> retry ${package} (${attempt}/2)" >&2
        sleep "$((attempt * 5))"
    done
    [[ "$built" -eq 1 ]] || exit 1
done

echo "OK: clean-build завершён для ${#packages[@]} пакетов"
