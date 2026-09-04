#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
cd "$repo_root"

mapfile -t all_packages < <(
    for staplerfile in */Staplerfile; do
        dirname "$staplerfile"
    done | sort
)

packages=()
if [[ "${1:-}" == '--all' ]]; then
    packages=("${all_packages[@]}")
    shift
else
    packages=("$@")
fi

[[ "${#packages[@]}" -gt 0 ]] || {
    echo 'Использование: tools/verify_artifacts.sh {--all|package...}' >&2
    exit 2
}

command -v rpm >/dev/null 2>&1 || {
    echo 'Для проверки RPM требуется команда rpm' >&2
    exit 2
}
command -v stplr-spec >/dev/null 2>&1 || {
    echo 'Для проверки метаданных требуется stplr-spec' >&2
    exit 2
}

contains_path() {
    local pattern="$1"
    local path
    for path in "${payload[@]}"; do
        # shellcheck disable=SC2053
        [[ "$path" == $pattern ]] && return 0
    done
    return 1
}

for package in "${packages[@]}"; do
    [[ -f "${package}/Staplerfile" ]] || {
        echo "Неизвестный пакет: ${package}" >&2
        exit 2
    }

    mapfile -t artifacts < <(find "$package" -maxdepth 1 -type f -name '*.rpm' -print)
    [[ "${#artifacts[@]}" -eq 1 ]] || {
        echo "${package}: ожидался один RPM, найдено ${#artifacts[@]}" >&2
        exit 1
    }

    artifact="${artifacts[0]}"
    package_name="$(stplr-spec get-field --path "${package}/Staplerfile" name)"
    recipe_version="$(stplr-spec get-field --path "${package}/Staplerfile" version)"
    recipe_release="$(stplr-spec get-field --path "${package}/Staplerfile" release)"
    recipe_architectures="$(
        stplr-spec get-field --path "${package}/Staplerfile" architectures
    )"
    repository="${NIVORA_EXPECTED_REPOSITORY:-default}"
    release_prefix="${NIVORA_RPM_RELEASE_PREFIX:-alt}"
    expected_name="${package_name}+stplr-${repository}"
    expected_epoch="${NIVORA_EXPECTED_EPOCH:-0}"
    expected_release="${release_prefix}${recipe_release}"

    case "${NIVORA_EXPECTED_ARCH:-$(uname -m)}" in
    amd64 | x86_64) expected_arch=x86_64; recipe_arch=amd64 ;;
    arm64 | aarch64) expected_arch=aarch64; recipe_arch=arm64 ;;
    *)
        echo "${package}: неизвестная ожидаемая архитектура" >&2
        exit 2
        ;;
    esac
    if [[ " $recipe_architectures " == *' all '* ]]; then
        expected_arch=noarch
    elif [[ " $recipe_architectures " != *" ${recipe_arch} "* ]]; then
        echo "${package}: рецепт не поддерживает ${recipe_arch}" >&2
        exit 1
    fi

    IFS='|' read -r rpm_name rpm_epoch rpm_version rpm_release rpm_arch < <(
        rpm -qp --queryformat '%{NAME}|%{EPOCHNUM}|%{VERSION}|%{RELEASE}|%{ARCH}\n' \
            "$artifact"
    )
    expected_nevra="${expected_name}-${expected_epoch}:${recipe_version}-${expected_release}.${expected_arch}"
    actual_nevra="${rpm_name}-${rpm_epoch}:${rpm_version}-${rpm_release}.${rpm_arch}"
    [[ "$actual_nevra" == "$expected_nevra" ]] || {
        echo "${package}: неверный NEVRA: ${actual_nevra}; ожидался ${expected_nevra}" >&2
        exit 1
    }

    mapfile -t payload < <(rpm -qlp "$artifact")
    contains_path "/usr/share/licenses/${package_name}/*" || {
        echo "${package}: отсутствует лицензия в собственном namespace" >&2
        exit 1
    }
    contains_path '/usr/share/licenses/LICENSE' && {
        echo "${package}: обнаружен общий конфликтный путь лицензии" >&2
        exit 1
    }

    recipe="$(<"${package}/Staplerfile")"
    if [[ "$recipe" == *'files-find-binary'* ]]; then
        contains_path '/usr/bin/*' || contains_path '/usr/sbin/*' || {
            echo "${package}: files-find-binary не добавил исполняемые файлы" >&2
            exit 1
        }
    fi
    if [[ "$recipe" == *'files-find-desktop'* ]]; then
        contains_path '/usr/share/applications/*.desktop' || {
            echo "${package}: files-find-desktop не добавил desktop-файл" >&2
            exit 1
        }
    fi
    if [[ "$recipe" == *'files-find-systemd'* ]]; then
        contains_path '/usr/lib/systemd/system/*' || {
            echo "${package}: files-find-systemd не добавил unit-файл" >&2
            exit 1
        }
    fi

    if [[ "$package" == 'balena-etcher' ]]; then
        for required_path in \
            /usr/bin/balena-etcher \
            /usr/lib/balena-etcher/balena-etcher \
            /usr/lib/balena-etcher/balenaEtcher \
            /usr/lib/balena-etcher/resources/etcher-util \
            /usr/share/applications/balena-etcher.desktop \
            /usr/share/pixmaps/balena-etcher.png; do
            contains_path "$required_path" || {
                echo "${package}: отсутствует компонент balenaEtcher: ${required_path}" >&2
                exit 1
            }
        done

        balena_command_target="$(
            rpm -qp --dump "$artifact" |
                awk '$1 == "/usr/bin/balena-etcher" {print $11}'
        )"
        balena_alias_target="$(
            rpm -qp --dump "$artifact" |
                awk '$1 == "/usr/lib/balena-etcher/balenaEtcher" {print $11}'
        )"
        [[ "$balena_command_target" == '../lib/balena-etcher/balena-etcher' ]] || {
            echo "${package}: неверная ссылка /usr/bin/balena-etcher" >&2
            exit 1
        }
        [[ "$balena_alias_target" == 'balena-etcher' ]] || {
            echo "${package}: обнаружена битая upstream-ссылка balenaEtcher" >&2
            exit 1
        }
    fi

    if [[ "$package" == 'chatgpt' ]]; then
        for command in cpio rpm2cpio; do
            command -v "$command" >/dev/null 2>&1 || {
                echo "${package}: для проверки AppArmor требуется ${command}" >&2
                exit 2
            }
        done
        for required_path in \
            /usr/bin/chatgpt \
            /usr/lib/chatgpt/ChatGPT \
            /usr/lib/chatgpt/codex-launcher \
            /usr/lib/chatgpt/resources/app.asar \
            /usr/share/applications/chatgpt.desktop \
            /usr/share/pixmaps/chatgpt.png \
            /etc/apparmor.d/chatgpt; do
            contains_path "$required_path" || {
                echo "${package}: отсутствует upstream-компонент ChatGPT: ${required_path}" >&2
                exit 1
            }
        done

        chatgpt_command_target="$(
            rpm -qp --dump "$artifact" |
                awk '$1 == "/usr/bin/chatgpt" {print $11}'
        )"
        [[ "$chatgpt_command_target" == '/usr/lib/chatgpt/ChatGPT' ]] || {
            echo "${package}: команда ChatGPT запускается не напрямую: ${chatgpt_command_target}" >&2
            exit 1
        }
        apparmor_profile="$(
            set +o pipefail
            rpm2cpio "$artifact" |
                cpio -i --quiet --to-stdout /etc/apparmor.d/chatgpt
        )"
        grep -Fq 'profile chatgpt "/usr/lib/chatgpt/ChatGPT"' \
            <<<"$apparmor_profile" || {
            echo "${package}: AppArmor profile не прикреплён к packaged binary" >&2
            exit 1
        }
        contains_path '*.musl.node' && {
            echo "${package}: обнаружены musl-варианты native-аддонов" >&2
            exit 1
        }
    fi

    if [[ "$package" == 'github-desktop' ]]; then
        for required_path in \
            /usr/bin/github-desktop \
            /opt/github-desktop/desktop \
            /opt/github-desktop/resources/app \
            /usr/share/applications/github-desktop.desktop \
            /usr/share/icons/hicolor/scalable/apps/github-desktop.svg; do
            contains_path "$required_path" || {
                echo "${package}: отсутствует компонент GitHub Desktop: ${required_path}" >&2
                exit 1
            }
        done

        github_desktop_target="$(
            rpm -qp --dump "$artifact" |
                awk '$1 == "/usr/bin/github-desktop" {print $11}'
        )"
        [[ "$github_desktop_target" == '/opt/github-desktop/desktop' ]] || {
            echo "${package}: команда GitHub Desktop запускается не напрямую" >&2
            exit 1
        }
    fi

    if [[ "$package" == 'ventoy' ]]; then
        for required_path in \
            /usr/bin/ventoy \
            '/opt/ventoy/VentoyGUI.*' \
            /opt/ventoy/boot/boot.img \
            /opt/ventoy/tool/VentoyWorker.sh \
            /opt/ventoy/ventoy/ventoy.disk.img.xz \
            /usr/share/applications/ventoy.desktop \
            /usr/share/icons/hicolor/128x128/apps/ventoy.png; do
            contains_path "$required_path" || {
                echo "${package}: отсутствует компонент Ventoy: ${required_path}" >&2
                exit 1
            }
        done
    fi

    while read -r path _ _ _ mode owner group _; do
        [[ "$owner" == root && "$group" == root ]] || {
            echo "${package}: неверный владелец ${owner}:${group} у ${path}" >&2
            exit 1
        }
        [[ "$path" == /usr/bin/* || "$path" == /usr/sbin/* ]] || continue
        [[ "$mode" == 0100755 || "$mode" == 0120000 ]] || {
            echo "${package}: неверные права ${mode} у ${path}" >&2
            exit 1
        }
    done < <(rpm -qp --dump "$artifact")

    echo "OK: ${package} ($(basename "$artifact"), ${#payload[@]} путей)"
done

echo "OK: payload проверен для ${#packages[@]} пакетов"
