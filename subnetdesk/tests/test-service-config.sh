#!/bin/bash
# Приложение переносит личность пользователя в конфигурацию root-службы через
# собственный диалог пароля поверх sudo, первую попытку которого он отправляет
# сам и с пустым значением. Пакет делает это сам, и тест следит, что связка
# «хелпер + drop-in» остаётся целой: путь в ExecStartPre должен совпадать с
# устанавливаемым именем, а отказ синхронизации не должен ронять службу.
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
recipe="${package_dir}/Staplerfile"
helper="${package_dir}/subnetdesk-service-config"
dropin="${package_dir}/nivora-config-sync.conf"

fail() {
    echo "test-service-config: $*" >&2
    exit 1
}

[[ -f "$helper" ]] || fail 'subnetdesk-service-config отсутствует'
[[ -x "$helper" ]] || fail 'subnetdesk-service-config не исполняемый'
[[ -f "$dropin" ]] || fail 'nivora-config-sync.conf отсутствует'

# Хелпер пишет в /root, поэтому без root он обязан отказаться, а не пытаться.
if output="$("$helper" 2>&1)"; then
    fail "без root хелпер завершился успешно: ${output}"
fi
grep -qF 'sudo subnetdesk-service-config' <<<"$output" ||
    fail "отказ без root не подсказывает команду: ${output}"

if output="$("$helper" --нет-такого 2>&1)"; then
    fail 'неизвестный аргумент принят'
fi

exec_line="$(grep -E '^ExecStartPre=' "$dropin" || true)"
[[ -n "$exec_line" ]] || fail 'в drop-in нет ExecStartPre'
# Ведущий «-»: без синхронизации служба всё равно должна подниматься.
[[ "$exec_line" == 'ExecStartPre=-'* ]] ||
    fail "ExecStartPre без ведущего '-' уронит службу: ${exec_line}"
grep -qF '/usr/bin/subnetdesk-service-config' <<<"$exec_line" ||
    fail "ExecStartPre указывает не на устанавливаемый путь: ${exec_line}"

# install-binary кладёт файл под его собственным именем, поэтому имя источника
# и путь в drop-in связаны жёстко.
grep -qE 'install-binary .*subnetdesk-service-config' "$recipe" ||
    fail 'рецепт не ставит subnetdesk-service-config через install-binary'
grep -qF 'subnetdesk.service.d/nivora-config-sync.conf' "$recipe" ||
    fail 'рецепт не ставит drop-in'

echo 'OK: синхронизация личности службы SubnetDesk не зависит от диалога sudo'
