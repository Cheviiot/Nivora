#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
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
    rpm_name="$(rpm -qp --queryformat '%{NAME}' "$artifact")"
    [[ "$rpm_name" == "${package_name}+stplr-"* ]] || {
        echo "${package}: неверное имя RPM: ${rpm_name}" >&2
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

    if [[ "$package" == 'claude-desktop' ]]; then
        for required_path in \
            /usr/bin/claude-alt \
            /usr/bin/claude-desktop-account2 \
            /usr/lib/claude-alt/claude-alt-bin \
            /usr/lib/claude-alt/resources/app.asar \
            /usr/lib/claude-alt/resources/icon.png \
            /usr/lib/claude-alt/resources/TrayIconLinux.png \
            /usr/lib/claude-alt/resources/TrayIconLinux-Dark.png \
            /usr/share/applications/com.anthropic.ClaudeAlt.desktop \
            /usr/share/icons/hicolor/512x512/apps/claude-alt.png; do
            contains_path "$required_path" || {
                echo "${package}: отсутствует компонент ClaudeAlt: ${required_path}" >&2
                exit 1
            }
        done
        contains_path '/usr/share/applications/claude-desktop-account2.desktop' && {
            echo "${package}: обнаружен устаревший desktop-файл второго профиля" >&2
            exit 1
        }
    fi

    while read -r path _ _ _ mode _; do
        [[ "$path" == /usr/bin/* || "$path" == /usr/sbin/* ]] || continue
        [[ "$mode" == 0100755 || "$mode" == 0120000 ]] || {
            echo "${package}: неверные права ${mode} у ${path}" >&2
            exit 1
        }
    done < <(rpm -qp --dump "$artifact")

    echo "OK: ${package} ($(basename "$artifact"), ${#payload[@]} путей)"
done

echo "OK: payload проверен для ${#packages[@]} пакетов"
