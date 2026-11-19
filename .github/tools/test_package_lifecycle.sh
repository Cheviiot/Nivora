#!/bin/bash
# Transactional install / upgrade / remove check for every Nivora package on a
# single ALT branch, inside a disposable container of that branch.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
# shellcheck source=.github/tools/lib/source_cache.sh
source "${script_dir}/lib/source_cache.sh"
# shellcheck source=.github/tools/lib/alt_branch.sh
source "${script_dir}/lib/alt_branch.sh"
# shellcheck source=.github/tools/lib/alt_builder.sh
source "${script_dir}/lib/alt_builder.sh"
cd "$repo_root"

branch="$(nivora_alt_branch)"
base_image="$(nivora_alt_branch_image "$branch")"
readonly rpm_image="nivora-lifecycle-${branch}:$$"
readonly cache_volume="nivora-lifecycle-${branch}-cache-$$"

# package | command | persistent state marker | desktop/unit | icon | sandbox
readonly -a lifecycle_package_catalog=(
    'anidesk|/usr/bin/anidesk|/home/nivora-test/.config/anidesk/nivora-lifecycle-state|/usr/share/applications/anidesk.desktop|/usr/share/icons/hicolor/256x256/apps/anidesk.png|/usr/lib/anidesk/chrome-sandbox'
    'antigravity|/usr/bin/antigravity|/home/nivora-test/.config/Antigravity/nivora-lifecycle-state|/usr/share/applications/antigravity.desktop|/usr/share/icons/hicolor/256x256/apps/com.google.Antigravity.png|/opt/antigravity/chrome-sandbox'
    'balena-etcher|/usr/bin/balena-etcher|/home/nivora-test/.config/balena-etcher/nivora-lifecycle-state|/usr/share/applications/balena-etcher.desktop|/usr/share/pixmaps/balena-etcher.png|/usr/lib/balena-etcher/chrome-sandbox'
    'chatgpt|/usr/bin/chatgpt|/home/nivora-test/.config/ChatGPT/nivora-lifecycle-state|/usr/share/applications/chatgpt.desktop|/usr/share/pixmaps/chatgpt.png|-'
    'claude|/usr/bin/claude-desktop|/home/nivora-test/.config/Claude/nivora-lifecycle-state|/usr/share/applications/com.anthropic.Claude.desktop|/usr/share/icons/hicolor/128x128/apps/claude-desktop.png|/usr/lib/claude-desktop/chrome-sandbox'
    'gnome-software-plugin-stplr|/usr/libexec/gnome-software-plugin-stplr/stplr-install|/home/nivora-test/.cache/gnome-software/nivora-lifecycle-state|-|-|-'
    'happ|/usr/bin/happ|/home/nivora-test/.config/happ/nivora-lifecycle-state|/usr/share/applications/Happ.desktop|/usr/lib/systemd/system/happd.service|-'
    'opencode|/usr/bin/opencode-desktop|/home/nivora-test/.config/opencode/nivora-lifecycle-state|/usr/share/applications/ai.opencode.desktop.desktop|/usr/share/icons/hicolor/128x128/apps/ai.opencode.png|/opt/OpenCode/chrome-sandbox'
    'parsec|/usr/bin/parsecd|/home/nivora-test/.parsec/nivora-lifecycle-state|/usr/share/applications/parsecd.desktop|/usr/share/icons/hicolor/256x256/apps/parsecd.png|-'
    'pineconemc|/usr/bin/pineconemc|/home/nivora-test/.config/pineconemc/nivora-lifecycle-state|/usr/share/applications/io.github.elyprismlauncher.ElyPrismLauncher.desktop|/usr/share/icons/hicolor/scalable/apps/io.github.elyprismlauncher.ElyPrismLauncher.svg|-'
    'tailscale|/usr/bin/tailscale|/var/lib/tailscale/nivora-lifecycle-state|/usr/lib/systemd/system/tailscaled.service|-|-'
    'telegram|/usr/bin/telegram-desktop|/home/nivora-test/.config/telegram-desktop/nivora-lifecycle-state|/usr/share/applications/org.telegram.desktop.desktop|/usr/share/icons/hicolor/256x256/apps/org.telegram.desktop.png|-'
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

case "${NIVORA_LIFECYCLE_PLAN_ONLY:-0}" in
0) ;;
1)
    printf 'BRANCH:%s\n' "$branch"
    printf 'RPM:%s\n' "$(
        IFS=,
        echo "${packages[*]}"
    )"
    exit 0
    ;;
*)
    echo 'NIVORA_LIFECYCLE_PLAN_ONLY must be 0 or 1' >&2
    exit 2
    ;;
esac

engine="$(nivora_alt_container_engine)" || exit 2

for command in curl find git python3 rpm rpmbuild sha256sum sqlite3 stplr-spec tar; do
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
docker_config=''
source_cache="${NIVORA_SOURCE_CACHE:-${XDG_CACHE_HOME:-${HOME}/.cache}/stplr/dl}"

cleanup() {
    "$engine" volume rm "$cache_volume" >/dev/null 2>&1 || true
    "$engine" image rm "$rpm_image" >/dev/null 2>&1 || true
    find "$work_dir" -mindepth 1 -delete
    rmdir "$work_dir"
    if [[ -n "$docker_config" ]]; then
        find "$docker_config" -mindepth 1 -delete
        rmdir "$docker_config"
    fi
}
trap cleanup EXIT

if [[ "$engine" == docker ]]; then
    docker_config="$(mktemp -d)"
    nivora_prepare_docker_config "$docker_config"
    export DOCKER_CONFIG="$docker_config"
fi

install -d "${work_dir}/builder" "${work_dir}/fixtures/previous-rpm"

NIVORA_STPLR_CHANNEL="${NIVORA_STPLR_CHANNEL:-stable}" \
    "${script_dir}/prepare_stplr.sh" "${work_dir}/builder/stplr"
chmod 0755 "$work_dir" "${work_dir}/builder"
nivora_prepare_alt_builder "$engine" "$branch" "$base_image" \
    "${work_dir}/builder" "$rpm_image"

missing=()
for package in "${packages[@]}"; do
    if ! "${script_dir}/verify_artifacts.sh" "$package" >/dev/null 2>&1; then
        missing+=("$package")
    fi
done
if [[ "${#missing[@]}" -gt 0 ]]; then
    "${script_dir}/clean_build.sh" "${missing[@]}"
fi
"${script_dir}/verify_artifacts.sh" "${packages[@]}"

"$engine" volume create "$cache_volume" >/dev/null
import_stplr_source_cache \
    "$engine" "$rpm_image" "$cache_volume" "$work_dir" "$source_cache" \
    "${packages[@]}"

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
        >"$spec"
    if [[ "$package" == antigravity ]]; then
        # Reproduce the previous two-launcher layout so the RPM transaction
        # must remove the obsolete desktop file, not merely omit a new one.
        cat >>"$spec" <<'EOF'
mkdir -p %{buildroot}/usr/share/applications
printf '[Desktop Entry]\nName=Antigravity\nType=Application\nExec=/usr/bin/antigravity\n' >%{buildroot}/usr/share/applications/com.google.Antigravity.desktop
cp %{buildroot}/usr/share/applications/com.google.Antigravity.desktop %{buildroot}/usr/share/applications/antigravity.desktop
EOF
    fi
    if [[ "$package" == tailscale ]]; then
        # Match the old RPM, which owned this file without config/noreplace.
        # The upgrade must preserve edits even when the predecessor did not
        # mark its defaults as configuration.
        cat >>"$spec" <<'EOF'
mkdir -p %{buildroot}/etc/default
printf 'PORT="41641"\nFLAGS=""\n' >%{buildroot}/etc/default/tailscaled
EOF
    fi
    printf '%s\n' '%files' "/usr/share/nivora-lifecycle-previous/${package}" >>"$spec"
    if [[ "$package" == antigravity ]]; then
        printf '%s\n' \
            '/usr/share/applications/com.google.Antigravity.desktop' \
            '/usr/share/applications/antigravity.desktop' >>"$spec"
    fi
    if [[ "$package" == tailscale ]]; then
        printf '%s\n' '/etc/default/tailscaled' >>"$spec"
    fi
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

previous_artifacts_dir="${NIVORA_PREVIOUS_ARTIFACTS_DIR:-}"

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

printf '%s\n' "${lifecycle_packages[@]}" >"${work_dir}/lifecycle-packages.txt"
: >"${work_dir}/previous-artifacts.tsv"

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

    rpm -qp --provides "${rpms[0]}" | grep -Eq "^${package}( = [0-9].*)?$"
    rpm -qp --obsoletes "${rpms[0]}" | grep -Fxq "$package"
    rpm -qp --conflicts "${rpms[0]}" | grep -Fxq "$package"
done <"${work_dir}/lifecycle-packages.txt"

cat >"${work_dir}/run-rpm.sh" <<'EOF'
#!/bin/bash
set -euo pipefail

scenario="${LIFECYCLE_SCENARIO:?LIFECYCLE_SCENARIO is required}"
case "$scenario" in
fresh | upgrade | distro-upgrade) ;;
*) echo "Unknown lifecycle scenario: $scenario" >&2; exit 2 ;;
esac

useradd --create-home nivora-test

IFS='|' read -r package command_path state_path expected_a expected_b sandbox_path \
    <<<"${LIFECYCLE_ENTRY:?LIFECYCLE_ENTRY is required}"
mapfile -t artifacts < <(find "/repo/${package}" -maxdepth 1 -type f -name '*.rpm' -print)
[[ "${#artifacts[@]}" -eq 1 ]]
artifact="${artifacts[0]}"
system_name="$(rpm -qp --queryformat '%{NAME}' "$artifact")"
current_evr="$(rpm -qp --queryformat '%{EPOCHNUM}:%{VERSION}-%{RELEASE}' "$artifact")"
current_arch="$(rpm -qp --queryformat '%{ARCH}' "$artifact")"
native_arch="$(rpm --eval '%{_arch}')"

if rpm -q "$system_name" >/dev/null 2>&1; then
    echo "${package}: ${scenario} lifecycle needs a clean container" >&2
    exit 1
fi
case "$current_arch" in
"$native_arch" | noarch) ;;
*)
    echo "${package}: current RPM architecture ${current_arch} is incompatible with ${native_arch}" >&2
    exit 1
    ;;
esac

echo "==> RPM lifecycle ${package}: ${scenario} (ALT ${NIVORA_ALT_BRANCH:-unknown})"
if [[ "$scenario" == distro-upgrade ]]; then
    [[ "$package" == gnome-software-plugin-stplr ]]
    # Exercise replacement of the real distribution RPM as well as an older
    # Nivora RPM. Both install the same GNOME Software plugin path.
    bash /usr/local/lib/nivora/alt_apt_network.sh run -qq install -y "$package"
    rpm -q "$package"
    [[ "$system_name" != "$package" ]]
fi
if [[ "$scenario" == upgrade ]]; then
    previous_artifact="/previous/${package}.rpm"
    previous_name="$(rpm -qp --queryformat '%{NAME}' "$previous_artifact")"
    previous_evr="$(rpm -qp --queryformat '%{EPOCHNUM}:%{VERSION}-%{RELEASE}' "$previous_artifact")"
    previous_arch="$(rpm -qp --queryformat '%{ARCH}' "$previous_artifact")"
    previous_summary="$(rpm -qp --queryformat '%{SUMMARY}' "$previous_artifact")"
    [[ "$previous_name" == "$system_name" ]] || {
        echo "${package}: previous RPM package identity ${previous_name} != ${system_name}" >&2
        exit 1
    }
    case "$previous_arch" in
    "$native_arch" | noarch) ;;
    *)
        echo "${package}: previous RPM architecture ${previous_arch} is incompatible with ${native_arch}" >&2
        exit 1
        ;;
    esac
    if [[ "$previous_summary" == \
        'Previous Nivora package fixture for lifecycle tests' ]]; then
        ! rpm -q bc >/dev/null 2>&1
        if [[ "$package" == tailscale ]]; then
            previous_config_flags="$(
                rpm -qp --queryformat '[%{FILEFLAGS}\t%{FILENAMES}\n]' "$previous_artifact" |
                    awk -F '\t' '$2 == "/etc/default/tailscaled" {print $1}'
            )"
            [[ "$previous_config_flags" == 0 ]] || {
                echo 'tailscale: previous fixture must own ordinary /etc/default/tailscaled' >&2
                exit 1
            }
        fi
    fi
    bash /usr/local/lib/nivora/alt_apt_network.sh run -qq install -y "$previous_artifact"
    [[ "$(rpm -q --queryformat '%{EPOCHNUM}:%{VERSION}-%{RELEASE}' "$system_name")" == "$previous_evr" ]]
    if [[ "$previous_summary" == \
        'Previous Nivora package fixture for lifecycle tests' ]]; then
        rpm -q bc >/dev/null
        if [[ "$package" == antigravity ]]; then
            test -f /usr/share/applications/com.google.Antigravity.desktop
            test -f /usr/share/applications/antigravity.desktop
        fi
    fi
    rpm -Uvh --test --nodeps --noscripts "$artifact" >/dev/null || {
        echo "${package}: previous RPM ${previous_evr} is not strictly older than ${current_evr}" >&2
        exit 1
    }
fi

tailscale_config=/etc/default/tailscaled
config_checksum=''
configure_tailscale() {
    test -f "$tailscale_config"
    printf '# Nivora lifecycle settings: %s\nPORT="41642"\nFLAGS=""\n' "$scenario" \
        >"$tailscale_config"
    config_checksum="$(sha256sum <"$tailscale_config")"
}
assert_tailscale_config() {
    local candidate
    for candidate in "$@"; do
        if [[ -f "$candidate" && "$(sha256sum <"$candidate")" == "$config_checksum" ]]; then
            return 0
        fi
    done
    echo "tailscale: ${scenario} lifecycle lost configured tailscaled settings" >&2
    exit 1
}
if [[ "$package" == tailscale && "$scenario" == upgrade ]]; then
    configure_tailscale
fi

# Existing user data must survive both the first installation and an upgrade,
# then removal. Check its bytes, not just that a filename is still present.
install -d "${state_path%/*}"
printf 'keep:%s:%s\n' "$package" "$scenario" >"$state_path"
state_checksum="$(sha256sum "$state_path")"
assert_state_preserved() {
    [[ -f "$state_path" && "$(sha256sum "$state_path")" == "$state_checksum" ]] || {
        echo "${package}: ${scenario} lifecycle changed persistent state: ${state_path}" >&2
        exit 1
    }
}
if [[ "$state_path" == /home/nivora-test/* ]]; then
    chown -R nivora-test:nivora-test /home/nivora-test
fi

# Capture what a real noninteractive RPM transaction shows the user. An
# informational first-install notice must never block an unattended upgrade.
install_log="$(mktemp)"
trap 'rm -f "$install_log"' EXIT
bash /usr/local/lib/nivora/alt_apt_network.sh run -qq install -y "$artifact" </dev/null 2>&1 | tee "$install_log"
rpm_license="$(rpm -qp --queryformat '%{LICENSE}' "$artifact")"
notice_license="$rpm_license"
notice_path="/usr/share/licenses/${package}/"
if [[ "$rpm_license" == LicenseRef-proprietary ]]; then
    notice_license='проприетарная'
    notice_path+=LICENSE.nivora
fi
expected_notices=1
if [[ "$scenario" == upgrade ]]; then expected_notices=0; fi
actual_notices="$(awk -v path="$notice_path" -v license=" — ${notice_license}" \
    'index($0, path) && index($0, license) { n++ } END { print n+0 }' "$install_log")"
[[ "$actual_notices" == "$expected_notices" ]] || {
    echo "$package: expected $expected_notices $rpm_license notices during $scenario, got $actual_notices" >&2
    exit 1
}
assert_state_preserved
if [[ "$package" == tailscale ]]; then
    if [[ "$scenario" == fresh ]]; then
        configure_tailscale
    fi
    assert_tailscale_config "$tailscale_config"
fi
rpm -q "$system_name"
[[ "$(rpm -q --queryformat '%{EPOCHNUM}:%{VERSION}-%{RELEASE}' "$system_name")" == "$current_evr" ]]
test -x "$command_path"
[[ "$expected_a" == '-' ]] || test -e "$expected_a"
[[ "$expected_b" == '-' ]] || test -e "$expected_b"
if [[ "$sandbox_path" != '-' ]]; then
    test -f "$sandbox_path"
    [[ "$(stat -c '%U:%G:%a' "$sandbox_path")" == 'root:root:4755' ]]
fi
if [[ "$package" == opencode ]]; then
    runuser -u nivora-test -- /opt/OpenCode/resources/opencode-cli --version >/dev/null
fi
if [[ "$package" == antigravity ]]; then
    test ! -e /usr/share/applications/com.google.Antigravity.desktop
    [[ "$(find /usr/share/applications -maxdepth 1 -type f -iname '*antigravity*.desktop' | wc -l)" -eq 1 ]]
    grep -Fxq 'MimeType=x-scheme-handler/antigravity;' /usr/share/applications/antigravity.desktop
    grep -Fq '>antigravity.desktop</launchable>' /usr/share/metainfo/com.google.Antigravity.metainfo.xml
fi
if [[ "$package" == gnome-software-plugin-stplr ]]; then
    bash -n "$command_path"
    python3 - <<'PY'
import ctypes
import glob
import os
import re
import subprocess
import xml.etree.ElementTree as ET

plugins = glob.glob('/usr/lib64/gnome-software/plugins-*/libgs_plugin_stplr.so')
assert len(plugins) == 1, f'duplicate/missing Stapler plugin: {plugins}'
path = plugins[0]
match = re.fullmatch(r'/usr/lib64/gnome-software/plugins-([0-9]+)/libgs_plugin_stplr.so', path)
assert match
# GNOME Software loads its private library before opening plugins. Reproduce
# that host without starting a graphical session or invoking package actions.
host = ctypes.CDLL(
    f'/usr/lib64/gnome-software/libgnomesoftware.so.{match[1]}',
    mode=os.RTLD_NOW | os.RTLD_GLOBAL,
)
plugin = ctypes.CDLL(path, mode=os.RTLD_NOW | os.RTLD_LOCAL)
plugin.gs_plugin_query_type.restype = ctypes.c_size_t
plugin_type = plugin.gs_plugin_query_type()
gobject = ctypes.CDLL('libgobject-2.0.so.0')
gobject.g_type_name.argtypes = [ctypes.c_size_t]
gobject.g_type_name.restype = ctypes.c_char_p
gobject.g_type_class_ref.argtypes = [ctypes.c_size_t]
gobject.g_type_class_ref.restype = ctypes.c_void_p
gobject.g_type_class_unref.argtypes = [ctypes.c_void_p]
assert gobject.g_type_name(plugin_type) == b'GsPluginStplr'
plugin_class = gobject.g_type_class_ref(plugin_type)
assert plugin_class, 'GNOME Software plugin class could not initialize'
gobject.g_type_class_unref(plugin_class)
owner = subprocess.check_output(['rpm', '-qf', '--queryformat', '%{NAME}', path], text=True)
assert owner != 'gnome-software-plugin-stplr', f'distribution plugin still owns {path}'
for helper in ('install', 'remove', 'refresh', 'repo-disable', 'repo-enable'):
    helper_path = f'/usr/libexec/gnome-software-plugin-stplr/stplr-{helper}'
    helper_owner = subprocess.check_output(['rpm', '-qf', '--queryformat', '%{NAME}', helper_path], text=True)
    assert helper_owner == owner, f'{helper_path} belongs to another package'
policy = '/usr/share/polkit-1/actions/dev.stplr.gnome-software-plugin-stplr.policy'
policy_owner = subprocess.check_output(['rpm', '-qf', '--queryformat', '%{NAME}', policy], text=True)
assert policy_owner == owner, f'{policy} belongs to another package'
document = ET.parse(policy).getroot()
actions = [action.get('id') for action in document.findall('action')]
assert document.tag == 'policyconfig' and actions and all(actions), f'{policy} defines no usable actions'
assert len(set(actions)) == len(actions), f'{policy} declares duplicate action IDs'
print(f'OK: native GNOME Software plugin loaded: {path} ({owner})')
PY
    if [[ "$scenario" == distro-upgrade ]]; then
        ! rpm -qa --queryformat '%{NAME}\n' | grep -Fxq "$package"
    fi
    if [[ "$scenario" == fresh ]]; then
        # Include the candidate working tree, including an autonomous recipe
        # update not committed yet. A clone of HEAD would test stale data.
        # Git belongs to this CI fixture, not to the plugin's runtime deps.
        bash /usr/local/lib/nivora/alt_apt_network.sh run -qq install -y git-core
        python3 - <<'PY'
from pathlib import Path
import shutil
import subprocess

source = Path('/repo')
target = Path('/tmp/nivora-catalog')
target.mkdir()
files = subprocess.check_output([
    'git', '-c', 'safe.directory=/repo', '-C', '/repo', 'ls-files',
    '-z', '--cached', '--others', '--exclude-standard',
]).decode().split('\0')
for filename in filter(None, files):
    original = source / filename
    if not original.is_file():
        continue
    destination = target / filename
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(original, destination)
subprocess.run(['git', '-C', str(target), 'init', '-q', '--initial-branch=main'], check=True)
subprocess.run(['git', '-C', str(target), 'add', '.'], check=True)
subprocess.run([
    'git', '-C', str(target), '-c', 'user.name=Nivora CI',
    '-c', 'user.email=ci@example.invalid', 'commit', '-qm', 'catalog fixture',
], check=True)
PY
        # This shell runs only in the disposable lifecycle container. Disable
        # default repositories and all network access during the catalog check.
        rm -f /usr/lib/stplr/repos.d/*.toml /etc/stplr/repos.d/*.toml \
            /etc/stplr/repo-overrides.d/*.toml
        install -d /etc/stplr
        cat >/etc/stplr/stplr.toml <<'CONFIG'
autoPull = false
useRootCmd = false
[[repo]]
name = "nivora"
url = "file:///tmp/nivora-catalog"
ref = "main"
CONFIG
        STPLR_AUTO_PULL=false unshare --net -- bash -euc '
            stplr -i=false refresh
            python3 /repo/.github/tools/check_gnome_catalog.py --repository /repo
        '
    fi
fi

bash /usr/local/lib/nivora/alt_apt_network.sh run -qq remove -y "$system_name"
assert_state_preserved
if [[ "$package" == tailscale ]]; then
    assert_tailscale_config "$tailscale_config" "${tailscale_config}.rpmsave"
fi
! rpm -q "$system_name"
if [[ "$package" == gnome-software-plugin-stplr ]]; then
    for path in \
        /usr/libexec/gnome-software-plugin-stplr/stplr-{install,remove,refresh,repo-disable,repo-enable} \
        /usr/share/polkit-1/actions/dev.stplr.gnome-software-plugin-stplr.policy; do
        [[ ! -e "$path" && ! -L "$path" ]]
    done
    ! find /usr/lib64/gnome-software -name libgs_plugin_stplr.so -print | grep -q .
fi
EOF

chmod 0755 "${work_dir}/run-rpm.sh"

while IFS= read -r lifecycle_entry; do
    # Never reuse the upgrade container for a first install: dependencies and
    # files left by the previous RPM could hide a broken clean installation.
    scenarios=(fresh upgrade)
    if [[ "${lifecycle_entry%%|*}" == gnome-software-plugin-stplr ]]; then
        scenarios+=(distro-upgrade)
    fi
    for scenario in "${scenarios[@]}"; do
        "$engine" run --rm --privileged \
            -e LIFECYCLE_ENTRY="$lifecycle_entry" \
            -e LIFECYCLE_SCENARIO="$scenario" \
            -e NIVORA_ALT_BRANCH="$branch" \
            -v "${repo_root}:/repo:ro" \
            -v "${work_dir}/fixtures/previous-rpm:/previous:ro" \
            -v "${work_dir}/run-rpm.sh:/run-lifecycle.sh:ro" \
            "$rpm_image" \
            /run-lifecycle.sh
    done
done <"${work_dir}/lifecycle-packages.txt"

echo "OK: lifecycle ALT ${branch} проверен для ${#packages[@]} пакетов"
