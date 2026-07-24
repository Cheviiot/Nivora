#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
# shellcheck source=tools/lib/source_cache.sh
source "${script_dir}/lib/source_cache.sh"
cd "$repo_root"

readonly stplr_version='0.1.1'
readonly stplr_archive_url="https://altlinux.space/stapler/stplr/releases/download/v${stplr_version}/stplr-${stplr_version}-linux-x86_64.tar.gz"
readonly stplr_archive_sha256='b1ec1e98c04ab928377d0cef1706e3dc62171b9e256f4bf36a219addc53117b8'
readonly deb_image="nivora-lifecycle-deb:$$"
readonly rpm_image="nivora-lifecycle-rpm:$$"
readonly deb_cache_volume="nivora-lifecycle-deb-cache-$$"
readonly deb_build_mode="${NIVORA_DEB_BUILD_MODE:-container}"

case "$deb_build_mode" in
container | host) ;;
*)
    echo "Неизвестный режим DEB-сборки: ${deb_build_mode}" >&2
    exit 2
    ;;
esac

# package | command | persistent state marker | desktop/unit | icon
readonly -a lifecycle_packages=(
    'clash-verge-rev|/usr/bin/clash-verge|/home/nivora-test/.local/share/io.github.clash-verge-rev.clash-verge-rev/nivora-lifecycle-state|/usr/share/applications/Clash Verge.desktop|/usr/share/icons/hicolor/128x128/apps/clash-verge.png'
    'claude|/usr/bin/claude-desktop|/home/nivora-test/.config/Claude/nivora-lifecycle-state|/usr/share/applications/com.anthropic.Claude.desktop|/usr/share/icons/hicolor/128x128/apps/claude-desktop.png'
    'codex|/usr/bin/codex-app|/home/nivora-test/.codex/nivora-lifecycle-state|/usr/share/applications/codex-app.desktop|/usr/share/icons/hicolor/512x512/apps/codex-app.png'
    'nivora-stplr|/usr/bin/sl|/home/nivora-test/.config/nivora-stplr/nivora-lifecycle-state|-|-'
    'opencode|/usr/bin/opencode-desktop|/home/nivora-test/.config/opencode/nivora-lifecycle-state|/usr/share/applications/opencode-desktop.desktop|/usr/share/icons/hicolor/128x128/apps/ai.opencode.desktop.png'
    'tailscale|/usr/bin/tailscale|/var/lib/tailscale/nivora-lifecycle-state|/usr/lib/systemd/system/tailscaled.service|-'
    'netbird|/usr/bin/netbird|/var/lib/netbird/nivora-lifecycle-state|/usr/lib/systemd/system/netbird.service|-'
    'chatbox|/usr/bin/chatbox|/home/nivora-test/.config/Chatbox/nivora-lifecycle-state|/usr/share/applications/xyz.chatboxapp.app.desktop|/usr/share/icons/hicolor/128x128/apps/xyz.chatboxapp.app.png'
)

for command in curl docker dpkg-deb find rpm rpmbuild sha256sum sqlite3 stplr-spec tar; do
    command -v "$command" >/dev/null 2>&1 || {
        echo "Для lifecycle-теста требуется команда ${command}" >&2
        exit 2
    }
done

[[ "$(uname -m)" == 'x86_64' ]] || {
    echo 'Lifecycle-тест сейчас поддерживает только x86_64 runner' >&2
    exit 2
}

work_dir="$(mktemp -d)"
source_cache="${NIVORA_SOURCE_CACHE:-${XDG_CACHE_HOME:-${HOME}/.cache}/stplr/dl}"
apparmor_userns_original=''

cleanup() {
    docker volume rm "$deb_cache_volume" >/dev/null 2>&1 || true
    docker image rm "$deb_image" >/dev/null 2>&1 || true
    docker image rm "$rpm_image" >/dev/null 2>&1 || true
    if [[ "$deb_build_mode" == 'host' && -d "$work_dir" ]]; then
        sudo chown -R "$(id -u):$(id -g)" "$work_dir" >/dev/null 2>&1 || true
    fi
    if [[ -n "$apparmor_userns_original" ]]; then
        sudo sysctl -q -w \
            "kernel.apparmor_restrict_unprivileged_userns=${apparmor_userns_original}" \
            >/dev/null 2>&1 || true
    fi
    find "$work_dir" -mindepth 1 -delete
    rmdir "$work_dir"
}
trap cleanup EXIT

install -d \
    "${work_dir}/builder" \
    "${work_dir}/fixtures/previous-deb" \
    "${work_dir}/fixtures/previous-rpm"

prepare_stplr() {
    local target="${work_dir}/builder/stplr"
    local archive actual

    if command -v stplr >/dev/null 2>&1 &&
        [[ "$(stplr version 2>/dev/null)" == "v${stplr_version}" ]]; then
        cp "$(command -v stplr)" "$target"
    else
        archive="${work_dir}/stplr.tar.gz"
        curl -fL \
            --retry 3 \
            --retry-all-errors \
            --connect-timeout 20 \
            --max-time 300 \
            -o "$archive" \
            "$stplr_archive_url"
        actual="$(sha256sum "$archive")"
        actual="${actual%% *}"
        [[ "$actual" == "$stplr_archive_sha256" ]] || {
            echo "Неверная SHA-256 stplr: ${actual}" >&2
            exit 1
        }
        tar -xzf "$archive" -C "${work_dir}/builder" stplr
    fi
    chmod 0755 "$work_dir" "${work_dir}/builder" "$target"
}

build_images() {
    cat >"${work_dir}/builder/Containerfile.deb" <<'EOF'
FROM ubuntu:24.04
ARG DEBIAN_FRONTEND=noninteractive
COPY stplr /usr/local/bin/stplr
RUN set -eux; \
    success=0; \
    for attempt in 1 2 3; do \
        if apt-get -o Acquire::Retries=2 -o Acquire::http::Timeout=20 update \
            && apt-get install -y ca-certificates binutils passwd python3 xz-utils zstd; then \
            success=1; \
            break; \
        fi; \
        sleep "$((attempt * 5))"; \
    done; \
    test "$success" -eq 1; \
    useradd --system --create-home stapler-builder; \
    mkdir -p /var/cache/stplr; \
    chown -R stapler-builder:stapler-builder /var/cache/stplr
EOF

    cat >"${work_dir}/builder/Containerfile.rpm" <<'EOF'
FROM registry.altlinux.org/sisyphus/base:latest
RUN for attempt in 1 2 3; do \
        apt-get -o Acquire::Retries=2 -o Acquire::http::Timeout=20 update \
        && apt-get dist-upgrade -y \
        && apt-get install -y ca-certificates stplr binutils python3 \
        && exit 0; \
        sleep "$((attempt * 5))"; \
    done; \
    exit 1
EOF

    docker build -t "$deb_image" -f "${work_dir}/builder/Containerfile.deb" \
        "${work_dir}/builder"
    docker build -t "$rpm_image" -f "${work_dir}/builder/Containerfile.rpm" \
        "${work_dir}/builder"
}

prepare_host_deb_builder() {
    if ! getent group wheel >/dev/null; then
        sudo groupadd --system wheel
    fi
    if ! getent passwd stapler-builder >/dev/null; then
        sudo useradd --system --create-home stapler-builder
    fi
    sudo usermod -a -G wheel stapler-builder
    sudo install -d -o stapler-builder -g stapler-builder /var/cache/stplr
    sudo -u stapler-builder test -x "${work_dir}/builder/stplr"

    if [[ -r /proc/sys/kernel/apparmor_restrict_unprivileged_userns ]]; then
        apparmor_userns_original="$(
            sysctl -n kernel.apparmor_restrict_unprivileged_userns
        )"
        if [[ "$apparmor_userns_original" != '0' ]]; then
            sudo sysctl -q -w kernel.apparmor_restrict_unprivileged_userns=0
        else
            apparmor_userns_original=''
        fi
    fi

    sudo -u stapler-builder unshare \
        --user --map-root-user --mount --pid --fork --uts --ipc --cgroup \
        true
}

build_deb_on_host() {
    local package="$1"
    local stage="${work_dir}/host-packages/${package}"
    local builder_home
    local -a artifacts

    install -d "$stage"
    cp -a "${package}/." "$stage/"
    find "$stage" -maxdepth 1 -type f \( -name '*.deb' -o -name '*.rpm' \) -delete
    sudo chown -R stapler-builder:stapler-builder "$stage"
    builder_home="$(getent passwd stapler-builder | cut -d: -f6)"

    (
        cd "$stage"
        sudo -u stapler-builder env \
            HOME="$builder_home" \
            TERM=xterm-256color \
            "${work_dir}/builder/stplr" \
            --interactive=false build --clean -s Staplerfile
    )

    mapfile -t artifacts < <(find "$stage" -maxdepth 1 -type f -name '*.deb' -print)
    [[ "${#artifacts[@]}" -eq 1 ]]
    install -m0644 "${artifacts[0]}" "${package}/$(basename "${artifacts[0]}")"
}

mapfile -t packages < <(
    printf '%s\n' "${lifecycle_packages[@]}" | cut -d '|' -f 1 | sort -u
)

missing_rpm=()
for package in "${packages[@]}"; do
    mapfile -t artifacts < <(find "$package" -maxdepth 1 -type f -name '*.rpm' -print)
    if [[ "${#artifacts[@]}" -ne 1 ]]; then
        missing_rpm+=("$package")
    fi
done
if [[ "${#missing_rpm[@]}" -gt 0 ]]; then
    "${script_dir}/clean_build.sh" "${missing_rpm[@]}"
fi
"${script_dir}/verify_artifacts.sh" "${packages[@]}"

prepare_stplr
build_images
if [[ "$deb_build_mode" == 'container' ]]; then
    docker volume create "$deb_cache_volume" >/dev/null
    import_stplr_source_cache \
        docker "$deb_image" "$deb_cache_volume" "$work_dir" "$source_cache" \
        "${packages[@]}"
else
    echo '==> DEB packages build directly on the host runner'
    prepare_host_deb_builder
fi

deb_is_current() {
    local package="$1"
    local expected_name expected_version expected_release artifact
    local -a existing

    mapfile -t existing < <(find "$package" -maxdepth 1 -type f -name '*.deb' -print)
    [[ "${#existing[@]}" -eq 1 ]] || return 1
    artifact="${existing[0]}"
    expected_name="$(stplr-spec get-field --path "${package}/Staplerfile" name)"
    expected_version="$(stplr-spec get-field --path "${package}/Staplerfile" version)"
    expected_release="$(stplr-spec get-field --path "${package}/Staplerfile" release)"

    [[ "$(dpkg-deb -f "$artifact" Package 2>/dev/null)" == "${expected_name}+stplr-default" ]] &&
        [[ "$(dpkg-deb -f "$artifact" Version 2>/dev/null)" == "${expected_version}-${expected_release}" ]]
}

for package in "${packages[@]}"; do
    if [[ "${NIVORA_REBUILD_DEB:-0}" != '1' ]] && deb_is_current "$package"; then
        echo "==> DEB reuse ${package}"
        continue
    fi
    echo "==> DEB build ${package}"
    find "$package" -maxdepth 1 -type f -name '*.deb' -delete
    if [[ "$deb_build_mode" == 'host' ]]; then
        build_deb_on_host "$package"
    else
        docker run --rm --privileged \
            -e TERM=xterm-256color \
            -v "${repo_root}/${package}:/app" \
            -v "${deb_cache_volume}:/var/cache/stplr" \
            -w /app \
            "$deb_image" \
            stplr --interactive=false build --clean -s Staplerfile
    fi
done

build_previous_deb() {
    local package="$1"
    local system_name="$2"
    local root="${work_dir}/previous-deb/${package}"

    install -d \
        "${root}/DEBIAN" \
        "${root}/usr/share/nivora-lifecycle-previous"
    printf '%s\n' \
        "Package: ${system_name}" \
        'Version: 0:0.0.2-1' \
        'Architecture: all' \
        'Maintainer: Nivora tests <noreply@example.invalid>' \
        "Provides: ${package}" \
        "Replaces: ${package}" \
        "Conflicts: ${package}" \
        'Description: Previous Nivora package fixture for lifecycle tests' \
        >"${root}/DEBIAN/control"
    printf 'previous fixture\n' \
        >"${root}/usr/share/nivora-lifecycle-previous/${package}"
    dpkg-deb --root-owner-group --build "$root" \
        "${work_dir}/fixtures/previous-deb/${package}.deb" >/dev/null
}

build_previous_rpm() {
    local package="$1"
    local system_name="$2"
    local topdir="${work_dir}/previous-rpmbuild/${package}"
    local spec="${topdir}/SPECS/previous.spec"
    local built

    install -d \
        "${topdir}/BUILD" \
        "${topdir}/BUILDROOT" \
        "${topdir}/RPMS" \
        "${topdir}/SOURCES" \
        "${topdir}/SPECS" \
        "${topdir}/SRPMS" \
        "${topdir}/TMP"
    printf '%s\n' \
        "Name: ${system_name}" \
        'Version: 0.0.2' \
        'Release: 1' \
        'Summary: Previous Nivora package fixture for lifecycle tests' \
        'Group: System/Configuration/Packaging' \
        'License: MIT' \
        'BuildArch: noarch' \
        "Provides: ${package}" \
        "Obsoletes: ${package}" \
        "Conflicts: ${package}" \
        '%description' \
        'Previous Nivora package fixture for lifecycle tests.' \
        '%install' \
        'mkdir -p %{buildroot}/usr/share/nivora-lifecycle-previous' \
        "printf 'previous fixture\\n' >%{buildroot}/usr/share/nivora-lifecycle-previous/${package}" \
        '%files' \
        "/usr/share/nivora-lifecycle-previous/${package}" \
        >"$spec"
    if ! rpmbuild \
        --define "_topdir ${topdir}" \
        --define "_tmppath ${topdir}/TMP" \
        -bb "$spec" >"${topdir}/build.log" 2>&1; then
        cat "${topdir}/build.log" >&2
        return 1
    fi
    built="$(find "${topdir}/RPMS" -type f -name '*.rpm' -print -quit)"
    [[ -n "$built" ]]
    cp "$built" "${work_dir}/fixtures/previous-rpm/${package}.rpm"
}

metadata_contains() {
    local value="$1"
    local expected="$2"
    value="${value//|/,}"
    value="${value// /}"
    [[ ",${value}," == *",${expected},"* ]]
}

printf '%s\n' "${lifecycle_packages[@]}" >"${work_dir}/lifecycle-packages.txt"

while IFS='|' read -r package _; do
    mapfile -t debs < <(find "$package" -maxdepth 1 -type f -name '*.deb' -print)
    mapfile -t rpms < <(find "$package" -maxdepth 1 -type f -name '*.rpm' -print)
    [[ "${#debs[@]}" -eq 1 && "${#rpms[@]}" -eq 1 ]] || {
        echo "${package}: ожидалось по одному DEB и RPM" >&2
        exit 1
    }
    build_previous_deb "$package" "$(dpkg-deb -f "${debs[0]}" Package)"
    build_previous_rpm "$package" "$(rpm -qp --queryformat '%{NAME}' "${rpms[0]}")"

    for field in Provides Replaces Conflicts; do
        value="$(dpkg-deb -f "${debs[0]}" "$field")"
        metadata_contains "$value" "$package" || {
            echo "${package}: DEB ${field} не содержит ${package}" >&2
            exit 1
        }
    done
    rpm -qp --provides "${rpms[0]}" | grep -Fxq "$package"
    rpm -qp --obsoletes "${rpms[0]}" | grep -Fxq "$package"
    rpm -qp --conflicts "${rpms[0]}" | grep -Fxq "$package"
done <"${work_dir}/lifecycle-packages.txt"

cat >"${work_dir}/run-deb.sh" <<'EOF'
#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
useradd --create-home nivora-test

is_installed() {
    [[ "$(dpkg-query -W -f='${db:Status-Abbrev}' "$1" 2>/dev/null || true)" == 'ii '* ]]
}

while IFS='|' read -r package command_path state_path expected_a expected_b; do
    mapfile -t artifacts < <(find "/repo/${package}" -maxdepth 1 -type f -name '*.deb' -print)
    [[ "${#artifacts[@]}" -eq 1 ]]
    artifact="${artifacts[0]}"
    system_name="$(dpkg-deb -f "$artifact" Package)"

    echo "==> DEB lifecycle ${package}"
    dpkg -i "/previous/${package}.deb"
    install -d "${state_path%/*}"
    printf 'keep\n' >"$state_path"
    if [[ "$state_path" == /home/nivora-test/* ]]; then
        chown -R nivora-test:nivora-test /home/nivora-test
    fi

    apt-get -qq install -y "$artifact"
    is_installed "$system_name"
    test -x "$command_path"
    [[ "$expected_a" == '-' ]] || test -e "$expected_a"
    [[ "$expected_b" == '-' ]] || test -e "$expected_b"

    apt-get -qq remove -y "$system_name"
    test -f "$state_path"
    ! is_installed "$system_name"
done </lifecycle-packages.txt
EOF

cat >"${work_dir}/run-rpm.sh" <<'EOF'
#!/bin/bash
set -euo pipefail

useradd --create-home nivora-test

while IFS='|' read -r package command_path state_path expected_a expected_b; do
    mapfile -t artifacts < <(find "/repo/${package}" -maxdepth 1 -type f -name '*.rpm' -print)
    [[ "${#artifacts[@]}" -eq 1 ]]
    artifact="${artifacts[0]}"
    system_name="$(rpm -qp --queryformat '%{NAME}' "$artifact")"

    echo "==> RPM lifecycle ${package}"
    rpm -ivh --quiet "/previous/${package}.rpm"
    install -d "${state_path%/*}"
    printf 'keep\n' >"$state_path"
    if [[ "$state_path" == /home/nivora-test/* ]]; then
        chown -R nivora-test:nivora-test /home/nivora-test
    fi

    apt-get -qq install -y "$artifact"
    rpm -q "$system_name"
    test -x "$command_path"
    [[ "$expected_a" == '-' ]] || test -e "$expected_a"
    [[ "$expected_b" == '-' ]] || test -e "$expected_b"

    apt-get -qq remove -y "$system_name"
    test -f "$state_path"
    ! rpm -q "$system_name"
done </lifecycle-packages.txt
EOF

chmod 0755 "${work_dir}/run-deb.sh" "${work_dir}/run-rpm.sh"

docker run --rm --privileged \
    -v "${repo_root}:/repo:ro" \
    -v "${work_dir}/fixtures/previous-deb:/previous:ro" \
    -v "${work_dir}/lifecycle-packages.txt:/lifecycle-packages.txt:ro" \
    -v "${work_dir}/run-deb.sh:/run-lifecycle.sh:ro" \
    "$deb_image" \
    /run-lifecycle.sh

docker run --rm --privileged \
    -v "${repo_root}:/repo:ro" \
    -v "${work_dir}/fixtures/previous-rpm:/previous:ro" \
    -v "${work_dir}/lifecycle-packages.txt:/lifecycle-packages.txt:ro" \
    -v "${work_dir}/run-rpm.sh:/run-lifecycle.sh:ro" \
    "$rpm_image" \
    /run-lifecycle.sh

echo "OK: DEB/RPM lifecycle проверен для ${#lifecycle_packages[@]} пакетов"
