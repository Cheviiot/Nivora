# Сопровождение Nivora

## Инварианты

- В репозитории ровно 15 каталогов с `Staplerfile`.
- Каталог совпадает с `name` и командой в README.
- Upstream-версия не меняется из-за патча рецепта; для этого повышается `release`.
- Desktop-id, AppStream component-id, units и пути данных не меняются без отдельной миграции.
- `replaces` содержит только имена системных пакетов.

Stapler сам добавляет текущее `name` в generated `Provides` и `Conflicts`. Поэтому в рецепте
переименованного пакета в `provides`, `replaces` и `conflicts` указан только прежний package ID.
Это исключает дубли нового ID в generated metadata.

## Названия

| Package ID | Основание |
|:--|:--|
| `clash-verge-rev` | Upstream-репозиторий и release title: Clash Verge Rev |
| `claude-desktop` | Upstream DEB: `Package: claude-desktop`; desktop-id `com.anthropic.Claude` сохранён |
| `codex` | Отображаемое имя `Codex`; команда и desktop-id `codex-app` сохранены |
| `nivora-stplr` | Собственный helper Nivora |

## Локальные проверки

```bash
tools/run_checks.sh
tools/package_updates.sh check-all
tools/verify_artifacts.sh --all
tools/test_package_transitions.sh
```

`run_checks.sh` выполняет `bash -n`, ShellCheck, Python compile, unit-тесты, validator и чтение
всех `Staplerfile` через `stplr-spec`.

`verify_artifacts.sh` сопоставляет готовые RPM с `files()`, проверяет владельцев путей,
права, desktop-файлы, systemd units, иконки, лицензии и метаданные совместимости.

`test_package_transitions.sh` собирает настоящие DEB текущей версии и использует настоящие
RPM из clean-build. Минимальные fixtures изображают только прежнее системное имя пакета и
предыдущую версию Nivora. В одноразовых Ubuntu и ALT-контейнерах через APT проверяются:

1. замена прежнего пакета фактическим пакетом Nivora;
2. обновление с предыдущей версии на текущую;
3. `Provides`, `Replaces` и `Conflicts`;
4. наличие команды, desktop-файла или systemd unit;
5. сохранение пользовательского состояния после удаления.

Полный переход проверяется для четырёх переименованных пакетов, а также `opencode`,
`tailscale`, `netbird` и `chatbox`. Остальные пакеты покрываются validator, clean-build и
проверкой payload.

Локально DEB собираются в привилегированном контейнере. На GitHub-hosted runner используется
`NIVORA_DEB_BUILD_MODE=host`: закреплённый stplr запускается непосредственно на одноразовом
Ubuntu runner, потому что вложенный sandbox stplr запрещён внутри Docker. Ubuntu 24.04 может
дополнительно блокировать непривилегированные user namespaces через AppArmor: тест временно
снимает только это ограничение, проверяет полный набор namespaces перед сборкой и
восстанавливает исходное значение при завершении. Для совместимости с моделью привилегий
Stapler временный builder включается в группу `wheel`, отсутствующую в Ubuntu по умолчанию.
Транзакционные сценарии в обоих режимах остаются изолированными в контейнерах.

## Обновление пакета

```bash
stplr-spec update-package package
stplr-spec verify-checksums --path package/Staplerfile
tools/run_checks.sh
tools/clean_build.sh package
```

Нестандартная логика обнаружения версий находится в `tools/package_updates.sh`, а каждый
`.stapler/update-check` вызывает его для своего package ID.

## Clean-build

```bash
tools/clean_build.sh package
tools/clean_build.sh --all
tools/verify_artifacts.sh --all
```

Скрипт использует `stplr-spec clean-build`, если команда доступна. Для более старого
`stplr-spec` выполняется эквивалентная сборка в контейнере ALT.

## Проверка миграции

Для каждого переименованного пакета нужно:

1. Собрать прежний и новый RPM/DEB.
2. Создать тестовый файл в каталоге данных.
3. Установить новый пакет поверх старого.
4. Проверить `Provides/Replaces/Conflicts`, payload и тестовый файл.
5. Проверить повторное обновление и удаление нового пакета.

Автоматизированная проверка выполняется командой `tools/test_package_transitions.sh` в
одноразовых контейнерах, а не на рабочей системе сопровождающего.
