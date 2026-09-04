#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
# shellcheck source=.github/tools/lib/source_cache.sh
source "${script_dir}/lib/source_cache.sh"
# shellcheck source=.github/tools/lib/package_compatibility.sh
source "${script_dir}/lib/package_compatibility.sh"
cd "$repo_root"

readonly deb_image="nivora-lifecycle-deb:$$"
readonly rpm_image="nivora-lifecycle-rpm:$$"
readonly deb_cache_volume="nivora-lifecycle-deb-cache-$$"
readonly rpm_cache_volume="nivora-lifecycle-rpm-cache-$$"
readonly deb_build_mode="${NIVORA_DEB_BUILD_MODE:-container}"
readonly deb_base_image="${NIVORA_UBUNTU_BUILDER_IMAGE:-ubuntu:24.04@sha256:33ceb71981b602c1a7443a53469e4dba065f7503eab3078a2d7a57a2ab987517}"
readonly rpm_base_image="${NIVORA_ALT_BUILDER_IMAGE:-registry.altlinux.org/sisyphus/base@sha256:1a6ab67cc12cfbe2419ed8b805ae6fd75ed036f9da7211b78876d1cd0083b7ba}"

for image in "$deb_base_image" "$rpm_base_image"; do
    if [[ "$image" != *@sha256:* && "${NIVORA_ALLOW_UNPINNED_IMAGE:-0}" != 1 ]]; then
        echo "Lifecycle image must use an immutable sha256 digest: ${image}" >&2
        exit 2
    fi
done

case "$deb_build_mode" in
container | host) ;;
*)
    echo "Неизвестный режим DEB-сборки: ${deb_build_mode}" >&2
    exit 2
    ;;
esac

# package | command | persistent state marker | desktop/unit | icon | sandbox
readonly -a lifecycle_package_catalog=(
    'anidesk|/usr/bin/anidesk|/home/nivora-test/.config/anidesk/nivora-lifecycle-state|/usr/share/applications/anidesk.desktop|/usr/share/icons/hicolor/256x256/apps/anidesk.png|/usr/lib/anidesk/chrome-sandbox'
    'balena-etcher|/usr/bin/balena-etcher|/home/nivora-test/.config/balena-etcher/nivora-lifecycle-state|/usr/share/applications/balena-etcher.desktop|/usr/share/pixmaps/balena-etcher.png|/usr/lib/balena-etcher/chrome-sandbox'
    'chatgpt|/usr/bin/chatgpt|/home/nivora-test/.config/ChatGPT/nivora-lifecycle-state|/usr/share/applications/chatgpt.desktop|/usr/share/pixmaps/chatgpt.png|-'
    'claude|/usr/bin/claude-desktop|/home/nivora-test/.config/Claude/nivora-lifecycle-state|/usr/share/applications/com.anthropic.Claude.desktop|/usr/share/icons/hicolor/128x128/apps/claude-desktop.png|/usr/lib/claude-desktop/chrome-sandbox'
    'distroshelf|/usr/bin/distroshelf|/home/nivora-test/.config/distroshelf/nivora-lifecycle-state|/usr/share/applications/com.ranfdev.DistroShelf.desktop|/usr/share/icons/hicolor/scalable/apps/com.ranfdev.DistroShelf.svg|-'
    'github-desktop|/usr/bin/github-desktop|/home/nivora-test/.config/GitHub Desktop/nivora-lifecycle-state|/usr/share/applications/github-desktop.desktop|/usr/share/icons/hicolor/scalable/apps/github-desktop.svg|/opt/github-desktop/chrome-sandbox'
    'happ|/usr/bin/happ|/home/nivora-test/.config/happ/nivora-lifecycle-state|/usr/share/applications/Happ.desktop|/usr/lib/systemd/system/happd.service|-'
    'nivora-cli|/usr/bin/nv|/home/nivora-test/.config/nivora-cli/nivora-lifecycle-state|-|-|-'
    'parsec|/usr/bin/parsecd|/home/nivora-test/.config/parsec/nivora-lifecycle-state|/usr/share/applications/parsecd.desktop|/usr/share/icons/hicolor/256x256/apps/parsecd.png|-'
    'pineconemc|/usr/bin/pineconemc|/home/nivora-test/.config/pineconemc/nivora-lifecycle-state|/usr/share/applications/io.github.elyprismlauncher.ElyPrismLauncher.desktop|/usr/share/icons/hicolor/scalable/apps/io.github.elyprismlauncher.ElyPrismLauncher.svg|-'
    'tailscale|/usr/bin/tailscale|/var/lib/tailscale/nivora-lifecycle-state|/usr/lib/systemd/system/tailscaled.service|-|-'
    'telegram|/usr/bin/telegram-desktop|/home/nivora-test/.config/telegram-desktop/nivora-lifecycle-state|/usr/share/applications/org.telegram.desktop.desktop|/usr/share/icons/hicolor/256x256/apps/org.telegram.desktop.png|-'
    'ventoy|/usr/bin/ventoy|/home/nivora-test/.config/ventoy/nivora-lifecycle-state|/usr/share/applications/ventoy.desktop|/usr/share/icons/hicolor/128x128/apps/ventoy.png|-'
    'vesktop|/usr/bin/vesktop|/home/nivora-test/.config/vesktop/nivora-lifecycle-state|/usr/share/applications/vesktop.desktop|/usr/share/icons/hicolor/scalable/apps/vesktop.svg|/opt/Vesktop/chrome-sandbox'
    'vintner|/usr/bin/vintner|/home/nivora-test/.config/vintner/nivora-lifecycle-state|-|-|-'
    'yandex-music|/usr/bin/yandex-music|/home/nivora-test/.config/yandex-music/nivora-lifecycle-state|/usr/share/applications/yandexmusic.desktop|/usr/share/icons/hicolor/256x256/apps/yandexmusic.png|/opt/YandexMusic/chrome-sandbox'
)

declare -a lifecycle_packages=("${lifecycle_package_catalog[@]}")
if [[ -n "${NIVORA_LIFECYCLE_PACKAGES:-}" ]]; then
    declare -a requested_packages
    declare -A known_packages=() selected_ids=()
    for lifecycle_entry in "${lifecycle_package_catalog[@]}"; do
        known_packages["${lifecycle_entry%%|*}"]="$lifecycle_entry"
    done
    IFS=',' read -r -a requested_packages <<<"$NIVORA_LIFECYCLE_PACKAGES"
    lifecycle_packages=()
    for package in "${requested_packages[@]}"; do
        [[ "$package" =~ ^[a-z0-9][a-z0-9-]*$ ]] || {
            echo "Некорректный package ID в NIVORA_LIFECYCLE_PACKAGES: ${package}" >&2
            exit 2
        }
        [[ -n "${known_packages[$package]:-}" ]] || {
            echo "Неизвестный lifecycle package: ${package}" >&2
            exit 2
        }
        [[ -z "${selected_ids[$package]:-}" ]] || {
            echo "Повторяющийся lifecycle package: ${package}" >&2
            exit 2
        }
        selected_ids["$package"]=1
        lifecycle_packages+=("${known_packages[$package]}")
    done
    [[ "${#lifecycle_packages[@]}" -gt 0 ]]
fi
readonly -a lifecycle_packages

mapfile -t packages < <(
    printf '%s\n' "${lifecycle_packages[@]}" | cut -d '|' -f 1 | sort -u
)

deb_packages=()
rpm_packages=()
for package in "${packages[@]}"; do
    if nivora_package_supports_distro "$package" ubuntu; then
        deb_packages+=("$package")
    elif [[ "$?" -ne 1 ]]; then
        exit 1
    fi
    if nivora_package_supports_distro "$package" altlinux; then
        rpm_packages+=("$package")
    elif [[ "$?" -ne 1 ]]; then
        exit 1
    fi
done
[[ "$(( ${#deb_packages[@]} + ${#rpm_packages[@]} ))" -gt 0 ]]

case "${NIVORA_LIFECYCLE_PLAN_ONLY:-0}" in
0) ;;
1)
    printf 'DEB:%s\n' "$(IFS=,; echo "${deb_packages[*]}")"
    printf 'RPM:%s\n' "$(IFS=,; echo "${rpm_packages[*]}")"
    exit 0
    ;;
*)
    echo 'NIVORA_LIFECYCLE_PLAN_ONLY must be 0 or 1' >&2
    exit 2
    ;;
esac

if command -v podman >/dev/null 2>&1; then
    engine=podman
elif command -v docker >/dev/null 2>&1; then
    engine=docker
else
    echo 'Для lifecycle-теста требуется Podman или Docker' >&2
    exit 2
fi

for command in curl dpkg-deb find git rpm rpmbuild sha256sum sqlite3 stplr-spec tar; do
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
    "$engine" volume rm "$deb_cache_volume" >/dev/null 2>&1 || true
    "$engine" volume rm "$rpm_cache_volume" >/dev/null 2>&1 || true
    "$engine" image rm "$deb_image" >/dev/null 2>&1 || true
    "$engine" image rm "$rpm_image" >/dev/null 2>&1 || true
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
    NIVORA_STPLR_CHANNEL=stable \
        "${script_dir}/prepare_stplr.sh" "${work_dir}/builder/stplr"
    chmod 0755 "$work_dir" "${work_dir}/builder"
}

build_images() {
    if [[ "${#deb_packages[@]}" -gt 0 ]]; then
        cat >"${work_dir}/builder/Containerfile.deb" <<EOF
FROM ${deb_base_image}
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
        sleep "\$((attempt * 5))"; \
    done; \
    test "\$success" -eq 1; \
    useradd --system --create-home stapler-builder; \
    mkdir -p /var/cache/stplr; \
    chown -R stapler-builder:stapler-builder /var/cache/stplr
EOF
        "$engine" build -t "$deb_image" \
            -f "${work_dir}/builder/Containerfile.deb" \
            "${work_dir}/builder"
    fi

    if [[ "${#rpm_packages[@]}" -gt 0 ]]; then
        cat >"${work_dir}/builder/Containerfile.rpm" <<EOF
FROM ${rpm_base_image}
RUN success=0; \
    for attempt in 1 2 3; do \
        apt-get -o Acquire::Retries=2 -o Acquire::http::Timeout=20 update \
        && apt-get dist-upgrade -y \
        && apt-get install -y ca-certificates stplr binutils python3 \
        && success=1 \
        && break; \
        sleep "\$((attempt * 5))"; \
    done; \
    test "\$success" -eq 1
COPY stplr /usr/local/bin/stplr
RUN chmod 0755 /usr/local/bin/stplr && /usr/local/bin/stplr version
EOF
        "$engine" build -t "$rpm_image" \
            -f "${work_dir}/builder/Containerfile.rpm" \
            "${work_dir}/builder"
    fi
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

missing_rpm=()
for package in "${rpm_packages[@]}"; do
    if ! "${script_dir}/verify_artifacts.sh" "$package" >/dev/null 2>&1; then
        missing_rpm+=("$package")
    fi
done
if [[ "${#rpm_packages[@]}" -gt 0 ]]; then
    if [[ "${#missing_rpm[@]}" -gt 0 ]]; then
        "${script_dir}/clean_build.sh" "${missing_rpm[@]}"
    fi
    "${script_dir}/verify_artifacts.sh" "${rpm_packages[@]}"
fi

prepare_stplr
build_images
if [[ "${#deb_packages[@]}" -gt 0 ]]; then
    if [[ "$deb_build_mode" == 'container' ]]; then
        "$engine" volume create "$deb_cache_volume" >/dev/null
        import_stplr_source_cache \
            "$engine" "$deb_image" "$deb_cache_volume" "$work_dir" "$source_cache" \
            "${deb_packages[@]}"
    else
        echo '==> DEB packages build directly on the host runner'
        prepare_host_deb_builder
    fi
fi
if [[ "${#rpm_packages[@]}" -gt 0 ]]; then
    "$engine" volume create "$rpm_cache_volume" >/dev/null
    import_stplr_source_cache \
        "$engine" "$rpm_image" "$rpm_cache_volume" "$work_dir" "$source_cache" \
        "${rpm_packages[@]}"
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

for package in "${deb_packages[@]}"; do
    if [[ "${NIVORA_REBUILD_DEB:-0}" != '1' ]] && deb_is_current "$package"; then
        echo "==> DEB reuse ${package}"
        continue
    fi
    echo "==> DEB build ${package}"
    find "$package" -maxdepth 1 -type f -name '*.deb' -delete
    if [[ "$deb_build_mode" == 'host' ]]; then
        build_deb_on_host "$package"
    else
        "$engine" run --rm --privileged \
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
    local current_version="$3"
    local root="${work_dir}/previous-deb/${package}"
    local previous_version="${current_version}~nivora.previous"

    install -d \
        "${root}/DEBIAN" \
        "${root}/usr/share/nivora-lifecycle-previous"
    printf '%s\n' \
        "Package: ${system_name}" \
        "Version: ${previous_version}" \
        'Architecture: all' \
        'Maintainer: Nivora tests <noreply@example.invalid>' \
        'Depends: bc' \
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
    local current_epoch="$3"
    local current_version="$4"
    local current_release="$5"
    local topdir="${work_dir}/previous-rpmbuild/${package}"
    local spec="${topdir}/SPECS/previous.spec"
    local built
    # RPM treats '-' and '.' as equivalent separators, while rpmbuild rejects
    # '-' in a Version field.  Normalising it keeps versions such as AniDesk's
    # 0.0.1-beta.7 valid and the trailing '~' orders the fixture before current.
    local previous_version="${current_version//-/.}~nivora.previous"

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
        "Epoch: ${current_epoch}" \
        "Version: ${previous_version}" \
        "Release: ${current_release}" \
        'Summary: Previous Nivora package fixture for lifecycle tests' \
        'Group: System/Configuration/Packaging' \
        'License: MIT' \
        'BuildArch: noarch' \
        'Requires: bc' \
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

previous_artifacts_dir="${NIVORA_PREVIOUS_ARTIFACTS_DIR:-${NIVORA_PREVIOUS_ARTIFACT_DIR:-}}"
if [[ -n "${NIVORA_PREVIOUS_ARTIFACTS_DIR:-}" &&
    -n "${NIVORA_PREVIOUS_ARTIFACT_DIR:-}" &&
    "${NIVORA_PREVIOUS_ARTIFACTS_DIR}" != "${NIVORA_PREVIOUS_ARTIFACT_DIR}" ]]; then
    echo 'NIVORA_PREVIOUS_ARTIFACT_DIR and NIVORA_PREVIOUS_ARTIFACTS_DIR disagree' >&2
    exit 1
fi

prepare_previous_deb_artifact() {
    local package="$1"
    local system_name="$2"
    local current_version="$3"
    if [[ -n "$previous_artifacts_dir" ]]; then
        [[ -f "${previous_artifacts_dir}/${package}.deb" ]] || {
            echo "${package}: external previous DEB is required" >&2
            return 1
        }
        cp "${previous_artifacts_dir}/${package}.deb" \
            "${work_dir}/fixtures/previous-deb/${package}.deb"
        printf '%s\tdeb\texternal\n' "$package" \
            >>"${work_dir}/previous-artifacts.tsv"
        return 0
    fi
    build_previous_deb "$package" "$system_name" "$current_version"
    printf '%s\tdeb\tsynthetic-transaction-fixture\n' "$package" \
        >>"${work_dir}/previous-artifacts.tsv"
}

prepare_previous_rpm_artifact() {
    local package="$1"
    local system_name="$2"
    local current_epoch="$3"
    local current_version="$4"
    local current_release="$5"
    if [[ -n "$previous_artifacts_dir" ]]; then
        [[ -f "${previous_artifacts_dir}/${package}.rpm" ]] || {
            echo "${package}: external previous RPM is required" >&2
            return 1
        }
        cp "${previous_artifacts_dir}/${package}.rpm" \
            "${work_dir}/fixtures/previous-rpm/${package}.rpm"
        printf '%s\trpm\texternal\n' "$package" \
            >>"${work_dir}/previous-artifacts.tsv"
        return 0
    fi
    build_previous_rpm \
        "$package" "$system_name" "$current_epoch" \
        "$current_version" "$current_release"
    printf '%s\trpm\tsynthetic-transaction-fixture\n' "$package" \
        >>"${work_dir}/previous-artifacts.tsv"
}

metadata_contains() {
    local value="$1"
    local expected="$2"
    value="${value//|/,}"
    value="${value// /}"
    [[ ",${value}," == *",${expected},"* ]]
}

printf '%s\n' "${lifecycle_packages[@]}" >"${work_dir}/lifecycle-packages.txt"
: >"${work_dir}/lifecycle-deb-packages.txt"
: >"${work_dir}/lifecycle-rpm-packages.txt"
while IFS= read -r lifecycle_entry; do
    package="${lifecycle_entry%%|*}"
    if nivora_package_supports_distro "$package" ubuntu; then
        printf '%s\n' "$lifecycle_entry" \
            >>"${work_dir}/lifecycle-deb-packages.txt"
    elif [[ "$?" -ne 1 ]]; then
        exit 1
    fi
    if nivora_package_supports_distro "$package" altlinux; then
        printf '%s\n' "$lifecycle_entry" \
            >>"${work_dir}/lifecycle-rpm-packages.txt"
    elif [[ "$?" -ne 1 ]]; then
        exit 1
    fi
done <"${work_dir}/lifecycle-packages.txt"
: >"${work_dir}/previous-artifacts.tsv"

while IFS='|' read -r package _; do
    mapfile -t debs < <(find "$package" -maxdepth 1 -type f -name '*.deb' -print)
    [[ "${#debs[@]}" -eq 1 ]] || {
        echo "${package}: ожидался ровно один DEB" >&2
        exit 1
    }
    recipe_name="$(stplr-spec get-field --path "${package}/Staplerfile" name)"
    recipe_version="$(stplr-spec get-field --path "${package}/Staplerfile" version)"
    recipe_release="$(stplr-spec get-field --path "${package}/Staplerfile" release)"
    recipe_architectures="$(
        stplr-spec get-field --path "${package}/Staplerfile" architectures
    )"
    deb_system_name="$(dpkg-deb -f "${debs[0]}" Package)"
    deb_current_version="$(dpkg-deb -f "${debs[0]}" Version)"
    deb_current_arch="$(dpkg-deb -f "${debs[0]}" Architecture)"
    [[ "$deb_system_name" == "${recipe_name}+stplr-default" ]] || {
        echo "${package}: DEB Package ${deb_system_name} не совпадает с рецептом" >&2
        exit 1
    }
    [[ "$deb_current_version" == "${recipe_version}-${recipe_release}" ]] || {
        echo "${package}: DEB Version ${deb_current_version} не совпадает с рецептом" >&2
        exit 1
    }
    if [[ " $recipe_architectures " == *' all '* ]]; then
        expected_deb_arch='all'
    else
        expected_deb_arch='amd64'
    fi
    [[ "$deb_current_arch" == "$expected_deb_arch" ]] || {
        echo "${package}: DEB Architecture ${deb_current_arch} != ${expected_deb_arch}" >&2
        exit 1
    }
    prepare_previous_deb_artifact \
        "$package" \
        "$deb_system_name" \
        "$deb_current_version"

    for field in Provides Replaces Conflicts; do
        value="$(dpkg-deb -f "${debs[0]}" "$field")"
        metadata_contains "$value" "$package" || {
            echo "${package}: DEB ${field} не содержит ${package}" >&2
            exit 1
        }
    done
done <"${work_dir}/lifecycle-deb-packages.txt"

while IFS='|' read -r package _; do
    mapfile -t rpms < <(find "$package" -maxdepth 1 -type f -name '*.rpm' -print)
    [[ "${#rpms[@]}" -eq 1 ]] || {
        echo "${package}: ожидался ровно один RPM" >&2
        exit 1
    }
    prepare_previous_rpm_artifact \
        "$package" \
        "$(rpm -qp --queryformat '%{NAME}' "${rpms[0]}")" \
        "$(rpm -qp --queryformat '%{EPOCHNUM}' "${rpms[0]}")" \
        "$(rpm -qp --queryformat '%{VERSION}' "${rpms[0]}")" \
        "$(rpm -qp --queryformat '%{RELEASE}' "${rpms[0]}")"

    rpm -qp --provides "${rpms[0]}" | grep -Fxq "$package"
    rpm -qp --obsoletes "${rpms[0]}" | grep -Fxq "$package"
    rpm -qp --conflicts "${rpms[0]}" | grep -Fxq "$package"
done <"${work_dir}/lifecycle-rpm-packages.txt"

cat >"${work_dir}/run-deb.sh" <<'EOF'
#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
useradd --create-home nivora-test

is_installed() {
    [[ "$(dpkg-query -W -f='${db:Status-Abbrev}' "$1" 2>/dev/null || true)" == 'ii '* ]]
}

IFS='|' read -r package command_path state_path expected_a expected_b sandbox_path \
    <<<"${LIFECYCLE_ENTRY:?LIFECYCLE_ENTRY is required}"
mapfile -t artifacts < <(find "/repo/${package}" -maxdepth 1 -type f -name '*.deb' -print)
[[ "${#artifacts[@]}" -eq 1 ]]
artifact="${artifacts[0]}"
system_name="$(dpkg-deb -f "$artifact" Package)"
current_version="$(dpkg-deb -f "$artifact" Version)"
current_arch="$(dpkg-deb -f "$artifact" Architecture)"
previous_artifact="/previous/${package}.deb"
previous_name="$(dpkg-deb -f "$previous_artifact" Package)"
previous_version="$(dpkg-deb -f "$previous_artifact" Version)"
previous_arch="$(dpkg-deb -f "$previous_artifact" Architecture)"
previous_description="$(dpkg-deb -f "$previous_artifact" Description)"
native_arch="$(dpkg --print-architecture)"

[[ "$previous_name" == "$system_name" ]] || {
    echo "${package}: previous DEB package identity ${previous_name} != ${system_name}" >&2
    exit 1
}
case "$current_arch" in
"$native_arch" | all) ;;
*)
    echo "${package}: current DEB architecture ${current_arch} is incompatible with ${native_arch}" >&2
    exit 1
    ;;
esac
case "$previous_arch" in
"$native_arch" | all) ;;
*)
    echo "${package}: previous DEB architecture ${previous_arch} is incompatible with ${native_arch}" >&2
    exit 1
    ;;
esac
dpkg --compare-versions "$previous_version" lt "$current_version" || {
    echo "${package}: previous DEB ${previous_version} is not older than ${current_version}" >&2
    exit 1
}

echo "==> DEB lifecycle ${package}"
if [[ "$previous_description" == \
    'Previous Nivora package fixture for lifecycle tests' ]]; then
    ! is_installed bc
fi
apt-get -qq install -y "$previous_artifact"
[[ "$(dpkg-query -W -f='${Version}' "$system_name")" == "$previous_version" ]]
if [[ "$previous_description" == \
    'Previous Nivora package fixture for lifecycle tests' ]]; then
    is_installed bc
fi
install -d "${state_path%/*}"
printf 'keep\n' >"$state_path"
if [[ "$state_path" == /home/nivora-test/* ]]; then
    chown -R nivora-test:nivora-test /home/nivora-test
fi

apt-get -qq install -y "$artifact"
is_installed "$system_name"
[[ "$(dpkg-query -W -f='${Version}' "$system_name")" == "$current_version" ]]
test -x "$command_path"
[[ "$expected_a" == '-' ]] || test -e "$expected_a"
[[ "$expected_b" == '-' ]] || test -e "$expected_b"
if [[ "$sandbox_path" != '-' ]]; then
    test -f "$sandbox_path"
    [[ "$(stat -c '%U:%G:%a' "$sandbox_path")" == 'root:root:4755' ]]
fi

apt-get -qq remove -y "$system_name"
test -f "$state_path"
! is_installed "$system_name"
EOF

cat >"${work_dir}/run-rpm.sh" <<'EOF'
#!/bin/bash
set -euo pipefail

useradd --create-home nivora-test

IFS='|' read -r package command_path state_path expected_a expected_b sandbox_path \
    <<<"${LIFECYCLE_ENTRY:?LIFECYCLE_ENTRY is required}"
mapfile -t artifacts < <(find "/repo/${package}" -maxdepth 1 -type f -name '*.rpm' -print)
[[ "${#artifacts[@]}" -eq 1 ]]
artifact="${artifacts[0]}"
system_name="$(rpm -qp --queryformat '%{NAME}' "$artifact")"
current_evr="$(rpm -qp --queryformat '%{EPOCHNUM}:%{VERSION}-%{RELEASE}' "$artifact")"
current_arch="$(rpm -qp --queryformat '%{ARCH}' "$artifact")"
previous_artifact="/previous/${package}.rpm"
previous_name="$(rpm -qp --queryformat '%{NAME}' "$previous_artifact")"
previous_evr="$(rpm -qp --queryformat '%{EPOCHNUM}:%{VERSION}-%{RELEASE}' "$previous_artifact")"
previous_arch="$(rpm -qp --queryformat '%{ARCH}' "$previous_artifact")"
previous_summary="$(rpm -qp --queryformat '%{SUMMARY}' "$previous_artifact")"
native_arch="$(rpm --eval '%{_arch}')"

[[ "$previous_name" == "$system_name" ]] || {
    echo "${package}: previous RPM package identity ${previous_name} != ${system_name}" >&2
    exit 1
}
case "$current_arch" in
"$native_arch" | noarch) ;;
*)
    echo "${package}: current RPM architecture ${current_arch} is incompatible with ${native_arch}" >&2
    exit 1
    ;;
esac
case "$previous_arch" in
"$native_arch" | noarch) ;;
*)
    echo "${package}: previous RPM architecture ${previous_arch} is incompatible with ${native_arch}" >&2
    exit 1
    ;;
esac

echo "==> RPM lifecycle ${package}"
if [[ "$previous_summary" == \
    'Previous Nivora package fixture for lifecycle tests' ]]; then
    ! rpm -q bc >/dev/null 2>&1
fi
apt-get -qq install -y "$previous_artifact"
[[ "$(rpm -q --queryformat '%{EPOCHNUM}:%{VERSION}-%{RELEASE}' "$system_name")" == "$previous_evr" ]]
if [[ "$previous_summary" == \
    'Previous Nivora package fixture for lifecycle tests' ]]; then
    rpm -q bc >/dev/null
fi
rpm -Uvh --test --nodeps --noscripts "$artifact" >/dev/null || {
    echo "${package}: previous RPM ${previous_evr} is not strictly older than ${current_evr}" >&2
    exit 1
}
install -d "${state_path%/*}"
printf 'keep\n' >"$state_path"
if [[ "$state_path" == /home/nivora-test/* ]]; then
    chown -R nivora-test:nivora-test /home/nivora-test
fi

apt-get -qq install -y "$artifact"
rpm -q "$system_name"
[[ "$(rpm -q --queryformat '%{EPOCHNUM}:%{VERSION}-%{RELEASE}' "$system_name")" == "$current_evr" ]]
test -x "$command_path"
[[ "$expected_a" == '-' ]] || test -e "$expected_a"
[[ "$expected_b" == '-' ]] || test -e "$expected_b"
if [[ "$sandbox_path" != '-' ]]; then
    test -f "$sandbox_path"
    [[ "$(stat -c '%U:%G:%a' "$sandbox_path")" == 'root:root:4755' ]]
fi

apt-get -qq remove -y "$system_name"
test -f "$state_path"
! rpm -q "$system_name"
EOF

chmod 0755 "${work_dir}/run-deb.sh" "${work_dir}/run-rpm.sh"

while IFS= read -r lifecycle_entry; do
    "$engine" run --rm --privileged \
        -e LIFECYCLE_ENTRY="$lifecycle_entry" \
        -v "${repo_root}:/repo:ro" \
        -v "${work_dir}/fixtures/previous-deb:/previous:ro" \
        -v "${work_dir}/run-deb.sh:/run-lifecycle.sh:ro" \
        "$deb_image" \
        /run-lifecycle.sh
done <"${work_dir}/lifecycle-deb-packages.txt"

while IFS= read -r lifecycle_entry; do
    "$engine" run --rm --privileged \
        -e LIFECYCLE_ENTRY="$lifecycle_entry" \
        -v "${repo_root}:/repo:ro" \
        -v "${work_dir}/fixtures/previous-rpm:/previous:ro" \
        -v "${work_dir}/run-rpm.sh:/run-lifecycle.sh:ro" \
        "$rpm_image" \
        /run-lifecycle.sh
done <"${work_dir}/lifecycle-rpm-packages.txt"

echo "OK: lifecycle проверен для ${#deb_packages[@]} DEB и ${#rpm_packages[@]} RPM пакетов"
