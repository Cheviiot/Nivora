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
            /usr/lib/claude-desktop/resources/TrayIconLinux.png \
            /usr/lib/claude-desktop/resources/TrayIconLinux-Dark.png \
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

    if [[ "$package" == 'codex' ]]; then
        for required_path in \
            /usr/bin/codex-app \
            /usr/bin/codex-computer-use-linux \
            /opt/codex-app/resources/app.asar \
            /opt/codex-app/resources/codex.asar \
            /opt/codex-app/resources/plugins/openai-bundled/.agents/plugins/marketplace.json \
            /opt/codex-app/resources/plugins/openai-bundled/plugins/computer-use/.codex-plugin/plugin.json \
            /opt/codex-app/resources/plugins/openai-bundled/plugins/computer-use/.mcp.json \
            /opt/codex-app/resources/plugins/openai-bundled/plugins/computer-use/assets/app-icon.png \
            /opt/codex-app/resources/plugins/openai-bundled/plugins/computer-use/bin/codex-computer-use-linux \
            /opt/codex-app/resources/plugins/openai-bundled/plugins/computer-use/bin/codex-computer-use-cosmic \
            /opt/codex-app/resources/plugins/openai-bundled/plugins/computer-use/bin/computer-use-linux-cosmic \
            /usr/share/applications/codex-app.desktop \
            /usr/share/icons/hicolor/512x512/apps/codex-app.png; do
            contains_path "$required_path" || {
                echo "${package}: отсутствует upstream-компонент Codex: ${required_path}" >&2
                exit 1
            }
        done

        codex_command_target="$(
            rpm -qp --dump "$artifact" |
                awk '$1 == "/usr/bin/codex-app" {print $11}'
        )"
        [[ "$codex_command_target" == '/opt/codex-app/codex-app' ]] || {
            echo "${package}: команда Codex запускается не напрямую: ${codex_command_target}" >&2
            exit 1
        }
        codex_computer_use_target="$(
            rpm -qp --dump "$artifact" |
                awk '$1 == "/usr/bin/codex-computer-use-linux" {print $11}'
        )"
        [[ "$codex_computer_use_target" == '/opt/codex-app/resources/plugins/openai-bundled/plugins/computer-use/bin/codex-computer-use-linux' ]] || {
            echo "${package}: неверная ссылка Computer Use: ${codex_computer_use_target}" >&2
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

    if [[ "$package" == 'opencode' ]]; then
        for required_path in \
            /usr/bin/opencode-desktop \
            /opt/OpenCode/ai.opencode.desktop \
            /opt/OpenCode/resources/app.asar \
            /usr/share/applications/opencode-desktop.desktop \
            /usr/share/icons/hicolor/128x128/apps/ai.opencode.desktop.png; do
            contains_path "$required_path" || {
                echo "${package}: отсутствует upstream-компонент OpenCode: ${required_path}" >&2
                exit 1
            }
        done

        opencode_command_target="$(
            rpm -qp --dump "$artifact" |
                awk '$1 == "/usr/bin/opencode-desktop" {print $11}'
        )"
        [[ "$opencode_command_target" == '/opt/OpenCode/ai.opencode.desktop' ]] || {
            echo "${package}: команда OpenCode запускается не напрямую: ${opencode_command_target}" >&2
            exit 1
        }
        contains_path '/usr/lib/opencode-desktop/*' && {
            echo "${package}: обнаружен удалённый wrapper OpenCode" >&2
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

    if [[ "$package" == 'yandex-browser-stable' ]]; then
        for command in cpio rpm2cpio; do
            command -v "$command" >/dev/null 2>&1 || {
                echo "${package}: для проверки desktop-файлов требуется ${command}" >&2
                exit 2
            }
        done
        for required_path in \
            /usr/bin/yandex-browser \
            /usr/bin/yandex-browser-stable \
            /opt/yandex/browser/yandex-browser \
            /opt/yandex/browser/yandex_browser \
            /opt/yandex/browser/yandex_browser-sandbox \
            /usr/share/appdata/yandex-browser.appdata.xml \
            /usr/share/applications/ru.yandex.desktop.browser.desktop \
            /usr/share/applications/yandex-browser.desktop \
            /usr/share/icons/hicolor/256x256/apps/yandex-browser.png \
            /usr/share/mime/packages/yandex-browser-yprotect.xml; do
            contains_path "$required_path" || {
                echo "${package}: отсутствует компонент Яндекс Браузера: ${required_path}" >&2
                exit 1
            }
        done
        contains_path '/etc/cron.daily/yandex-browser' && {
            echo "${package}: обнаружена upstream cron-задача обновления" >&2
            exit 1
        }
        contains_path '/etc/xdg/autostart/yandex-browser_user_setup.desktop' && {
            echo "${package}: обнаружен нежелательный upstream autostart" >&2
            exit 1
        }

        compatibility_desktop="$(
            set +o pipefail
            rpm2cpio "$artifact" |
                cpio -i --quiet --to-stdout \
                    /usr/share/applications/yandex-browser.desktop
        )"
        canonical_desktop="$(
            set +o pipefail
            rpm2cpio "$artifact" |
                cpio -i --quiet --to-stdout \
                    /usr/share/applications/ru.yandex.desktop.browser.desktop
        )"
        desktop_entry_hidden() {
            awk '
                $0 == "[Desktop Entry]" { in_entry = 1; next }
                /^\[/ { in_entry = 0 }
                in_entry && $0 == "NoDisplay=true" { found = 1 }
                END { exit !found }
            '
        }
        desktop_entry_hidden <<<"$compatibility_desktop" || {
            echo "${package}: совместимый desktop-id виден в меню приложений" >&2
            exit 1
        }
        if desktop_entry_hidden <<<"$canonical_desktop"; then
            echo "${package}: canonical desktop-id ошибочно скрыт" >&2
            exit 1
        fi
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
